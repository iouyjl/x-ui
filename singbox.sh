#!/bin/sh

# 获取IP地址
IP_ADDRESSES=($(hostname -I))
apt update && apt install -y supervisor wget unzip iproute2 curl jq

# 下载最新版sing-box
LATEST_VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    armv7l)
        ARCH="armv7"
        ;;
    *)
        ARCH="amd64"
        ;;
esac

echo "下载Sing-box ${LATEST_VERSION} for ${ARCH}..."
wget -q "https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
tar -xzf "sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
cd "sing-box-${LATEST_VERSION}-linux-${ARCH}"
mv sing-box /usr/local/bin/singbox
chmod +x /usr/local/bin/singbox

# 创建singbox用户
useradd --system --no-create-home --shell /usr/sbin/nologin singbox

# 创建systemd服务
cat <<EOF >/etc/systemd/system/singbox.service
[Unit]
Description=singbox Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=singbox
Group=nogroup
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/singbox run -c /etc/singbox/config.json
ExecReload=/usr/local/bin/singbox reload -c /etc/singbox/config.json
LimitNOFILE=51200
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

# 创建配置目录
mkdir -p /etc/singbox

# 生成UUID和密码
UUID=$(cat /proc/sys/kernel/random/uuid)
SHADOWSOCKS_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
TROJAN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
SOCKS_USER=$(openssl rand -base64 6 | tr -d '/+')
SOCKS_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

# 创建优化配置 - 移除Hysteria2或使用简单配置
cat > /etc/singbox/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-inbound",
      "listen": "::",
      "listen_port": 10000,
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SHADOWSOCKS_PASSWORD}",
      "network": "tcp,udp"
    },
    {
      "type": "vmess",
      "tag": "vmess-inbound",
      "listen": "::",
      "listen_port": 20000,
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "GunService"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-inbound",
      "listen": "::",
      "listen_port": 30000,
      "users": [
        {
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/ws",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-inbound",
      "listen": "::",
      "listen_port": 40000,
      "users": [
        {
          "password": "${UUID}"
        }
      ],
      "tls": {
        "enabled": false
      }
    },
    {
      "type": "socks",
      "tag": "socks-inbound",
      "listen": "::",
      "listen_port": 50000,
      "users": [
        {
          "username": "${SOCKS_USER}",
          "password": "${SOCKS_PASSWORD}"
        }
      ],
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "inbound": [
          "ss-inbound",
          "vmess-inbound",
          "trojan-inbound",
          "hysteria2-inbound",
          "socks-inbound"
        ],
        "outbound": "direct"
      }
    ],
    "auto_detect_interface": true,
    "override_android_vpn": true
  }
}
EOF

# 设置权限
chown -R singbox:nogroup /etc/singbox
chmod 644 /etc/singbox/config.json

# 先测试配置文件
echo "测试配置文件..."
if /usr/local/bin/singbox check -c /etc/singbox/config.json; then
    echo "✓ 配置文件检查通过"
else
    echo "✗ 配置文件检查失败，使用简化配置..."
    # 使用更简单的配置
    cat > /etc/singbox/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-inbound",
      "listen": "0.0.0.0",
      "listen_port": 10000,
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SHADOWSOCKS_PASSWORD}"
    },
    {
      "type": "vmess",
      "tag": "vmess-inbound",
      "listen": "0.0.0.0",
      "listen_port": 20000,
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ]
    },
    {
      "type": "trojan",
      "tag": "trojan-inbound",
      "listen": "0.0.0.0",
      "listen_port": 30000,
      "users": [
        {
          "password": "${TROJAN_PASSWORD}"
        }
      ]
    },
    {
      "type": "socks",
      "tag": "socks-inbound",
      "listen": "0.0.0.0",
      "listen_port": 50000,
      "users": [
        {
          "username": "${SOCKS_USER}",
          "password": "${SOCKS_PASSWORD}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
fi

# 启动服务
systemctl daemon-reload
systemctl enable singbox.service
systemctl restart singbox.service

sleep 2

# 检查服务状态
if systemctl is-active --quiet singbox.service; then
    echo "✓ Sing-box 服务启动成功"
else
    echo "✗ Sing-box 服务启动失败，查看日志..."
    journalctl -u singbox.service -n 20 --no-pager
    
    # 尝试使用更简单的配置
    echo "尝试使用最基本配置..."
    cat > /etc/singbox/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "listen_port": 10000,
      "method": "chacha20-ietf-poly1305",
      "password": "${SHADOWSOCKS_PASSWORD}"
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
    
    systemctl restart singbox.service
    sleep 1
fi

# 性能优化
# 调整内核参数
cat >> /etc/sysctl.conf <<EOF
# 性能优化参数
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
EOF

sysctl -p 2>/dev/null

# 启用BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p 2>/dev/null

# 优化文件限制
cat > /etc/security/limits.d/singbox.conf <<EOF
singbox soft nofile 51200
singbox hard nofile 51200
* soft nofile 51200
* hard nofile 51200
EOF

# 获取IP信息
v4=$(curl -s4m6 ip.sb -k 2>/dev/null || curl -s4m6 icanhazip.com 2>/dev/null || echo "127.0.0.1")
if [ "$v4" = "127.0.0.1" ]; then
    # 尝试从接口获取IP
    v4=$(ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
fi

# 生成分享链接
# 1. Shadowsocks链接
SS_LINK="ss://$(echo -n "chacha20-ietf-poly1305:${SHADOWSOCKS_PASSWORD}@${v4}:10000" | base64 -w 0)#SingBox_SS"

# 2. VMESS链接
VMESS_CONFIG=$(cat <<EOF | base64 -w 0
{
  "v": "2",
  "ps": "SingBox_VMESS",
  "add": "${v4}",
  "port": "20000",
  "id": "${UUID}",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF
)
VMESS_LINK="vmess://${VMESS_CONFIG}"

# 3. Trojan链接
TROJAN_LINK="trojan://${TROJAN_PASSWORD}@${v4}:30000?sni=${v4}#SingBox_Trojan"

# 5. SOCKS链接
SOCKS_LINK="socks://${SOCKS_USER}:${SOCKS_PASSWORD}@${v4}:50000#SingBox_SOCKS5"

# 生成Clash配置
cat > /root/singbox_clash.yaml <<EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  # Shadowsocks
  - name: "SingBox-SS"
    type: ss
    server: ${v4}
    port: 10000
    cipher: chacha20-ietf-poly1305
    password: "${SHADOWSOCKS_PASSWORD}"
    udp: true
    
  # VMESS
  - name: "SingBox-VMESS"
    type: vmess
    server: ${v4}
    port: 20000
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    
  # Trojan
  - name: "SingBox-Trojan"
    type: trojan
    server: ${v4}
    port: 30000
    password: "${TROJAN_PASSWORD}"
    sni: ${v4}
      
  # SOCKS5
  - name: "SingBox-SOCKS5"
    type: socks5
    server: ${v4}
    port: 50000
    username: "${SOCKS_USER}"
    password: "${SOCKS_PASSWORD}"
    
proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "SingBox-SS"
      - "SingBox-VMESS"
      - "SingBox-Trojan"
      - "DIRECT"
      
  - name: "🌍 国外媒体"
    type: select
    proxies:
      - "🚀 节点选择"
      - "DIRECT"

rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - MATCH,🚀 节点选择
EOF

# 输出配置信息
echo ""
echo "=================================================================================="
echo "                     Sing-box 代理服务器安装完成"
echo "=================================================================================="
echo "服务器IP：$v4"
echo "安装时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================================================="
echo ""
echo "📱 直接导入链接："
echo ""
echo "1. Shadowsocks (推荐):"
echo "   $SS_LINK"
echo ""
echo "2. VMESS:"
echo "   $VMESS_LINK"
echo ""
echo "3. Trojan:"
echo "   $TROJAN_LINK"
echo ""
echo "4. SOCKS5:"
echo "   $SOCKS_LINK"
echo ""
echo "=================================================================================="
echo "📁 配置文件路径："
echo "主配置: /etc/singbox/config.json"
echo "Clash配置: /root/singbox_clash.yaml (可直接导入软路由)"
echo "=================================================================================="
echo ""
echo "🔧 服务管理命令："
echo "启动: systemctl start singbox"
echo "停止: systemctl stop singbox"
echo "重启: systemctl restart singbox"
echo "状态: systemctl status singbox"
echo "日志: journalctl -u singbox -f"
echo ""
echo "📊 测试连接："
echo "检查端口: nc -zv $v4 10000"
echo "检查端口: nc -zv $v4 20000"
echo "检查端口: nc -zv $v4 30000"
echo "检查端口: nc -zv $v4 50000"
echo "=================================================================================="

# 显示服务状态
echo ""
echo "📊 服务运行状态："
systemctl --no-pager status singbox.service

# 检查端口监听
echo ""
echo "🔍 端口监听状态："
netstat -tlnp | grep singbox || echo "等待服务启动..."
sleep 3
netstat -tlnp | grep singbox || echo "使用: systemctl restart singbox 重启服务"
