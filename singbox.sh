#!/bin/sh

# 安装依赖
apt update && apt install -y wget curl unzip

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) ARCH="amd64" ;;
esac

# 获取最新版本
VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

echo "下载Sing-box v${VERSION} for ${ARCH}..."
wget -q "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${ARCH}.tar.gz"
tar -xzf "sing-box-${VERSION}-linux-${ARCH}.tar.gz"
cd "sing-box-${VERSION}-linux-${ARCH}"
mv sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 生成配置
mkdir -p /etc/singbox

# 生成密码
SS_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
UUID=$(cat /proc/sys/kernel/random/uuid)
TROJAN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

# 最简单的配置文件
cat > /etc/singbox/config.json <<EOF
{
  "log": {
    "level": "info",
    "output": "/var/log/singbox.log"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "listen_port": 10000,
      "method": "chacha20-ietf-poly1305",
      "password": "${SS_PASSWORD}"
    },
    {
      "type": "vmess",
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
      "listen": "0.0.0.0",
      "listen_port": 50000,
      "users": [
        {
          "username": "user",
          "password": "pass"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 测试配置
echo "测试配置文件..."
if /usr/local/bin/sing-box check -c /etc/singbox/config.json; then
    echo "✓ 配置文件检查通过"
else
    echo "生成更简化的配置..."
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
      "password": "${SS_PASSWORD}"
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
fi

# 创建systemd服务
cat > /etc/systemd/system/singbox.service <<EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/singbox/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable singbox.service
systemctl start singbox.service

# 等待并检查
sleep 2

if systemctl is-active --quiet singbox.service; then
    echo "✓ Sing-box 服务启动成功"
    
    # 获取IP
    IP=$(curl -s4 ip.sb 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
    
    echo ""
    echo "========================================================"
    echo "Sing-box 安装完成！"
    echo "服务器IP: $IP"
    echo "========================================================"
    echo ""
    echo "🔗 配置链接:"
    echo ""
    echo "1. Shadowsocks:"
    echo "   ss://$(echo -n "chacha20-ietf-poly1305:${SS_PASSWORD}@${IP}:10000" | base64 -w 0)#SS_Proxy"
    echo ""
    echo "2. VMESS:"
    echo "   vmess://$(echo -n '{"v":"2","ps":"VMESS_Proxy","add":"'${IP}'","port":"20000","id":"'${UUID}'","aid":"0","net":"tcp","type":"none","tls":"none"}' | base64 -w 0)"
    echo ""
    echo "3. Trojan:"
    echo "   trojan://${TROJAN_PASSWORD}@${IP}:30000?sni=${IP}#Trojan_Proxy"
    echo ""
    echo "4. SOCKS5:"
    echo "   socks5://user:pass@${IP}:50000#SOCKS5_Proxy"
    echo ""
    echo "========================================================"
    echo "📊 服务状态: systemctl status singbox"
    echo "📝 查看日志: journalctl -u singbox -f"
    echo "🔄 重启服务: systemctl restart singbox"
    echo "========================================================"
    
    # 显示监听端口
    echo ""
    echo "📡 监听端口:"
    netstat -tlnp | grep sing-box || ss -tlnp | grep sing-box
    
else
    echo "✗ 服务启动失败，查看日志..."
    journalctl -u singbox.service -n 20 --no-pager
    echo ""
    echo "尝试手动启动调试..."
    /usr/local/bin/sing-box run -c /etc/singbox/config.json
fi
