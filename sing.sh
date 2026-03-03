#!/bin/bash
set -e

# 定义自定义配置（自动生成随机密码/UUID）
UUID="$(cat /proc/sys/kernel/random/uuid)"
SS_PASSWORD="GameSS@$(date +%s | md5sum | head -c 8)"
SK5_USER="gameuser"
SK5_PASSWORD="GameSK5@$(date +%s | md5sum | head -c 8)"
MAIN_PORT=443
SS_PORT=60001
SK5_PORT=60002

# 步骤1：系统优化 + 关闭防火墙
echo "===== 开始系统优化和关闭防火墙 ====="
systemctl stop firewalld && systemctl disable firewalld || true
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config || true

# 网络优化配置
cat > /etc/sysctl.d/99-game-network.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=0
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=1200
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_max_tw_buckets=5000
net.core.somaxconn=65535
net.core.netdev_max_backlog=65535
net.ipv4.tcp_max_orphans=65535
net.ipv4.udp_mem=1048576 2097152 4194304
net.core.optmem_max=81920
EOF

sysctl --system > /dev/null 2>&1

# 安装依赖
if command -v apt > /dev/null; then
    apt update && apt install -y wget curl unzip tar > /dev/null 2>&1
elif command -v yum > /dev/null; then
    yum install -y wget curl unzip tar > /dev/null 2>&1
fi

# 步骤2：安装Sing-box
echo "===== 开始安装Sing-box ====="
bash -c "$(curl -fsSL https://sing-box.app/install.sh)" > /dev/null 2>&1

# 步骤3：生成Sing-box配置文件
echo "===== 生成游戏专用Sing-box配置 ====="
mkdir -p /usr/local/etc/sing-box /var/log/sing-box
cat > /usr/local/etc/sing-box/config.json << EOF
{
  "log": {
    "level": "warn",
    "output": "/var/log/sing-box/sing-box.log"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": ${MAIN_PORT},
      "udp": true,
      "users": [
        {
          "uuid": "${UUID}",
          "alter_id": 0
        }
      ],
      "transport": {
        "type": "tcp",
        "tcp": {
          "fast_open": true,
          "no_delay": true
        }
      }
    },
    {
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "listen_port": ${SS_PORT},
      "udp": true,
      "method": "chacha20-ietf-poly1305",
      "password": "${SS_PASSWORD}"
    },
    {
      "type": "socks",
      "listen": "0.0.0.0",
      "listen_port": ${SK5_PORT},
      "udp": true,
      "users": [
        {
          "username": "${SK5_USER}",
          "password": "${SK5_PASSWORD}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "transport": {
        "tcp": {
          "fast_open": true,
          "no_delay": true
        }
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_is_private": true,
        "outbound": "block"
      }
    ],
    "auto_detect_interface": true,
    "final": "direct"
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/lib/sing-box/cache.db"
    }
  }
}
EOF

# 步骤4：启动Sing-box并设置开机自启
echo "===== 启动Sing-box服务 ====="
systemctl daemon-reload
systemctl start sing-box
systemctl enable sing-box > /dev/null 2>&1

# 步骤5：生成快捷查看命令 + 输出连接信息
echo "===== 设置快捷查看命令 ====="
echo "alias sing-conf='cat /usr/local/etc/sing-box/config.json'" >> /root/.bashrc
source /root/.bashrc

# 获取服务器公网IP
SERVER_IP=$(curl -s icanhazip.com || curl -s ifconfig.me)

# 生成SS链接编码
SS_URL="ss://$(echo -n "chacha20-ietf-poly1305:${SS_PASSWORD}" | base64 -w 0)@${SERVER_IP}:${SS_PORT}#Game-SS"

# 输出最终信息
echo -e "\n===== 部署完成！游戏专用Sing-box连接信息 ====="
echo "服务器IP: ${SERVER_IP}"
echo "----------------------------------------"
echo "VLESS 链接: vless://${UUID}@${SERVER_IP}:${MAIN_PORT}?encryption=none&security=none&type=tcp&headerType=none#Game-VLESS"
echo "SS    链接: ${SS_URL}"
echo "Socks5链接: socks5://${SK5_USER}:${SK5_PASSWORD}@${SERVER_IP}:${SK5_PORT}#Game-SK5"
echo "----------------------------------------"
echo "快捷查看配置: 输入 sing-conf 即可"
echo "查看服务状态: systemctl status sing-box"