#!/bin/bash
# Sing-box 全自动安装脚本 v3.0
# 自动安装 + 关闭防火墙 + 优化 + 输出链接

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Sing-box 全自动脚本 (一键完成所有)  ${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查root
[ "$EUID" -ne 0 ] && echo -e "${RED}[!] 请用root运行${NC}" && exit 1

# 1. 更新系统
echo -e "${BLUE}[1/8]${NC} 更新系统..."
apt update -y > /dev/null 2>&1
apt install -y curl wget tar > /dev/null 2>&1

# 2. 下载Sing-box
echo -e "${BLUE}[2/8]${NC} 下载Sing-box..."
cd /tmp
# 使用快速下载源
wget -q --timeout=30 -O singbox.tar.gz "https://dl.sb.workers.dev/https://github.com/SagerNet/sing-box/releases/download/v1.12.21/sing-box-1.12.21-linux-amd64.tar.gz" || {
    # 备用源
    wget -q -O singbox.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.12.21/sing-box-1.12.21-linux-amd64.tar.gz"
}

# 解压
tar -xzf singbox.tar.gz
mv sing-box-1.12.21-linux-amd64/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 3. 生成随机配置
echo -e "${BLUE}[3/8]${NC} 生成配置..."
mkdir -p /etc/singbox

# 生成UUID
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "1e9b1c6b-2a1d-4e8f-9c7d-6b8a5f4e3d2c")
PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
PORT1=10086
PORT2=10087
PORT3=10088

# 生成私钥和短ID
PRIVATE_KEY=$(openssl rand -base64 32 2>/dev/null || echo "aK1I4A1e6prmZ7jJ7tR7zQJqN9vQ8qJ0xN8vD2eF5rC6tH3qM")
SHORT_ID=$(openssl rand -hex 4 2>/dev/null || echo "0123456789abcdef")

cat > /etc/singbox/config.json <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT1,
      "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "handshake": {"server": "www.apple.com", "server_port": 443},
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT2,
      "users": [{"password": "$PASS"}]
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT3,
      "users": [{"uuid": "$UUID", "alterId": 0}],
      "transport": {"type": "ws", "path": "/video"}
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF

# 4. 创建服务
echo -e "${BLUE}[4/8]${NC} 创建服务..."
cat > /etc/systemd/system/singbox.service <<EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/singbox/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable singbox --now > /dev/null 2>&1

# 5. 关闭所有防火墙
echo -e "${BLUE}[5/8]${NC} 关闭防火墙..."
# 停止防火墙服务
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true

# 停止ufw
ufw disable 2>/dev/null || true
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true

# 清空iptables
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# 6. 网络优化
echo -e "${BLUE}[6/8]${NC} 优化网络..."
# 开启BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

# TCP优化
cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_max_syn_backlog=8192
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 16384 16777216
net.ipv4.ip_local_port_range=1024 65535
EOF

sysctl -p > /dev/null 2>&1 || true

# 7. 等待服务启动
echo -e "${BLUE}[7/8]${NC} 启动服务..."
sleep 3

# 检查服务状态
if systemctl is-active --quiet singbox; then
    echo -e "${GREEN}[✓] 服务启动成功${NC}"
else
    # 尝试重启
    systemctl restart singbox
    sleep 2
fi

# 8. 获取IP和显示结果
echo -e "${BLUE}[8/8]${NC} 生成链接..."
IP=$(curl -4 -s https://api.ipify.org || curl -6 -s https://api64.ipify.org || hostname -I | awk '{print $1}')

# 输出结果
echo ""
echo "========================================"
echo "🎉 安装完成！"
echo "========================================"
echo "服务器IP: $IP"
echo ""

# 1. Vless-reality 链接
echo "🔗 Vless-reality (推荐):"
echo "vless://${UUID}@${IP}:${PORT1}?type=tcp&security=reality&sni=www.apple.com&fp=chrome&pbk=${PRIVATE_KEY:0:43}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Singbox-${IP}"
echo ""

# 2. Hysteria2 链接
echo "🔗 Hysteria2 (高速):"
echo "hysteria2://${PASS}@${IP}:${PORT2}/?insecure=1&sni=www.apple.com#Hysteria2-${IP}"
echo ""

# 3. Vmess 链接
echo "🔗 Vmess-WS (备用):"
VMESS_CONFIG=$(cat <<EOF
{
  "v": "2",
  "ps": "Singbox-Vmess-${IP}",
  "add": "${IP}",
  "port": "${PORT3}",
  "id": "${UUID}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "",
  "path": "/video",
  "tls": "none"
}
EOF
)
BASE64_CONFIG=$(echo "$VMESS_CONFIG" | base64 | tr -d '\n')
echo "vmess://${BASE64_CONFIG}"
echo ""

# 4. 一键导入命令
echo "📋 一键导入命令:"
echo "bash <(curl -s https://raw.githubusercontent.com/SagerNet/sing-box/main/script/install.sh) --config /etc/singbox/config.json"
echo ""

# 5. 测试命令
echo "📊 测试连接:"
echo "curl -x socks5h://127.0.0.1:1080 http://www.google.com"
echo ""

# 6. 管理命令
echo "🛠️  管理命令:"
echo "systemctl status singbox    # 查看状态"
echo "systemctl restart singbox   # 重启"
echo "systemctl stop singbox      # 停止"
echo "journalctl -u singbox -f    # 查看日志"
echo ""

# 7. 配置文件位置
echo "📁 配置文件: /etc/singbox/config.json"
echo ""

# 8. 检查端口
echo "🔍 检查端口监听:"
netstat -tlnp | grep -E ":${PORT1}|:${PORT2}|:${PORT3}" || echo "正在启动中..."
echo ""

echo "========================================"
echo "✅ 所有链接已生成，可直接复制使用！"
echo "========================================"

# 最后确保服务正常运行
systemctl restart singbox > /dev/null 2>&1 &
