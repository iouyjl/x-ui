#!/bin/bash
set -e

# 定义自定义配置（你可以修改这里的UUID、密码、端口）
UUID="$(cat /proc/sys/kernel/random/uuid)"  # 自动生成随机UUID
SS_PASSWORD="GameSS@$(date +%s | md5sum | head -c 8)"  # 自动生成随机SS密码
SK5_USER="gameuser"
SK5_PASSWORD="GameSK5@$(date +%s | md5sum | head -c 8)"  # 自动生成随机SK5密码
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

# 步骤2：安装Xray
echo "===== 开始安装Xray ====="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root > /dev/null 2>&1

# 步骤3：生成Xray配置文件
echo "===== 生成游戏专用Xray配置 ====="
mkdir -p /usr/local/etc/xray /var/log/xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": ${MAIN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": ${SS_PORT},
            "xver": 1
          },
          {
            "dest": ${SK5_PORT},
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "udp": true
    },
    {
      "port": ${SS_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method": "chacha20-ietf-poly1305",
        "password": "${SS_PASSWORD}",
        "udp": true
      },
      "sniffing": {
        "enabled": true
      }
    },
    {
      "port": ${SK5_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "${SK5_USER}",
            "pass": "${SK5_PASSWORD}"
          }
        ],
        "udp": true,
        "userLevel": 0
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "streamSettings": {
        "sockopt": {
          "mark": 255,
          "tcpFastOpen": true
        }
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# 步骤4：启动Xray并设置开机自启
echo "===== 启动Xray服务 ====="
systemctl daemon-reload
systemctl start xray
systemctl enable xray > /dev/null 2>&1

# 步骤5：生成快捷查看命令 + 输出连接信息
echo "===== 设置快捷查看命令 ====="
echo "alias xray-conf='cat /usr/local/etc/xray/config.json'" >> /root/.bashrc
source /root/.bashrc

# 获取服务器公网IP
SERVER_IP=$(curl -s icanhazip.com || curl -s ifconfig.me)

# 生成SS链接编码
SS_ENCODED=$(echo -n "${SS_PASSWORD}" | base64 -w 0)
SS_URL="ss://$(echo -n "chacha20-ietf-poly1305:${SS_PASSWORD}" | base64 -w 0)@${SERVER_IP}:${SS_PORT}#Game-SS"

# 输出最终信息
echo -e "\n===== 部署完成！游戏专用Xray连接信息 ====="
echo "服务器IP: ${SERVER_IP}"
echo "----------------------------------------"
echo "VLESS 链接: vless://${UUID}@${SERVER_IP}:${MAIN_PORT}?encryption=none&security=none&type=tcp&headerType=none#Game-VLESS"
echo "SS    链接: ${SS_URL}"
echo "Socks5链接: socks5://${SK5_USER}:${SK5_PASSWORD}@${SERVER_IP}:${SK5_PORT}#Game-SK5"
echo "----------------------------------------"
echo "快捷查看配置: 输入 xray-conf 即可"
echo "查看服务状态: systemctl status xray"