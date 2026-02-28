#!/bin/bash
# ==========================================
# 极简版 Sing-box 全自动部署脚本 (精准优化版)
# 基于实测通畅的第二版修改：压低延迟 + SK5明文配置
# ==========================================

echo -e "\n[1/5] 正在清理防火墙拦截并注入满血版网络优化(压低延迟)..."
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget tar openssl iptables >/dev/null 2>&1

systemctl stop firewalld >/dev/null 2>&1
systemctl disable firewalld >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT 2>/dev/null
iptables -P FORWARD ACCEPT 2>/dev/null
iptables -P OUTPUT ACCEPT 2>/dev/null
iptables -F 2>/dev/null

# 注入满血版 BBR 和 TCP 缓冲区优化（解决延迟高的核心）
cat > /etc/sysctl.d/99-singbox-optimize.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=1200
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_notsent_lowat=16384
EOF
sysctl --system >/dev/null 2>&1

echo -e "[2/5] 正在下载并安装 sing-box 内核..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) CPU="amd64" ;;
  aarch64) CPU="arm64" ;;
  *) echo "不支持的架构: $ARCH" && exit 1 ;;
esac

SB_VER=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ -z "$SB_VER" ]; then SB_VER="1.11.4"; fi

wget -qO sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-${CPU}.tar.gz"
tar -xzf sing-box.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf sing-box.tar.gz sing-box-*
mkdir -p /etc/sing-box

echo -e "[3/5] 正在生成参数与自签证书..."
UUID=$(/usr/local/bin/sing-box generate uuid)
KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(/usr/local/bin/sing-box generate rand --hex 4)
SERVER_IP=$(curl -s4m5 icanhazip.com || curl -s6m5 icanhazip.com)

# 分配端口 (使用更稳妥的赋值方式防止出错)
PORTS=$(shuf -i 10000-65000 -n 5)
P_VLESS=$(echo "$PORTS" | sed -n '1p')
P_VMESS=$(echo "$PORTS" | sed -n '2p')
P_HY2=$(echo "$PORTS" | sed -n '3p')
P_TUIC=$(echo "$PORTS" | sed -n '4p')
P_SOCKS=$(echo "$PORTS" | sed -n '5p')

# 生成自签证书
openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/private.key
openssl req -new -x509 -days 365 -key /etc/sing-box/private.key -out /etc/sing-box/cert.pem -subj "/CN=www.bing.com" >/dev/null 2>&1

echo -e "[4/5] 正在写入配置文件..."
# 这里的 SK5 账号密码已硬编码为 123
cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless", "tag": "vless-in", "listen": "::", "listen_port": $P_VLESS,
      "users": [ { "uuid": "$UUID", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true, "server_name": "apple.com",
        "reality": { "enabled": true, "handshake": { "server": "apple.com", "server_port": 443 }, "private_key": "$PRIVATE_KEY", "short_id": ["$SHORT_ID"] }
      }
    },
    {
      "type": "vmess", "tag": "vmess-in", "listen": "::", "listen_port": $P_VMESS,
      "users": [ { "uuid": "$UUID", "alterId": 0 } ],
      "transport": { "type": "ws", "path": "/$UUID" }
    },
    {
      "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": $P_HY2,
      "users": [ { "password": "$UUID" } ],
      "ignore_client_bandwidth": false,
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "/etc/sing-box/cert.pem", "key_path": "/etc/sing-box/private.key" }
    },
    {
      "type": "tuic", "tag": "tuic-in", "listen": "::", "listen_port": $P_TUIC,
      "users": [ { "uuid": "$UUID", "password": "$UUID" } ],
      "congestion_control": "bbr",
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "/etc/sing-box/cert.pem", "key_path": "/etc/sing-box/private.key" }
    },
    {
      "type": "socks", "tag": "socks-in", "listen": "::", "listen_port": $P_SOCKS,
      "users": [ { "username": "123", "password": "123" } ]
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF

echo -e "[5/5] 正在启动并检查 Sing-box 服务状态..."
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sing-box >/dev/null 2>&1
sleep 2

if ! systemctl is-active --quiet sing-box; then
    echo -e "\n\033[31m启动失败！\033[0m排查日志如下："
    journalctl -u sing-box -n 15 --no-pager
    exit 1
fi

clear
echo "=========================================================="
echo -e "\033[32m✅ 服务端部署成功！状态：运行中\033[0m"
echo "满血版缓冲优化已加载，请测试延迟表现。"
echo "=========================================================="
echo -e "\n\033[33m1. Vless-Reality (最推荐)\033[0m"
echo "vless://$UUID@$SERVER_IP:$P_VLESS?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#Vless-Reality"

echo -e "\n\033[33m2. Vmess-WS\033[0m"
VMESS_JSON="{\"add\":\"$SERVER_IP\",\"aid\":\"0\",\"host\":\"\",\"id\":\"$UUID\",\"net\":\"ws\",\"path\":\"/$UUID\",\"port\":\"$P_VMESS\",\"ps\":\"Vmess-WS\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}"
echo "vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

echo -e "\n\033[33m3. Hysteria-2 (需开启允许不安全证书)\033[0m"
echo "hysteria2://$UUID@$SERVER_IP:$P_HY2?insecure=1&sni=www.bing.com&alpn=h3#Hysteria2"

echo -e "\n\033[33m4. Tuic-v5 (需开启允许不安全证书)\033[0m"
echo "tuic://$UUID:$UUID@$SERVER_IP:$P_TUIC?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1#Tuic5"

echo -e "\n\033[33m5. Socks5 (已修改为纯明文，账号密码 123)\033[0m"
echo "socks5://123:123@$SERVER_IP:$P_SOCKS#Socks5"
echo "=========================================================="
