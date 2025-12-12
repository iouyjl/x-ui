#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}开始安装和配置Sing-box代理...${NC}"

# 1. 安装必要工具
apt update && apt install -y wget curl net-tools iptables-persistent

# 2. 下载并安装sing-box
echo -e "${YELLOW}下载Sing-box...${NC}"
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) ARCH="amd64" ;;
esac

# 使用稳定版本
wget -q "https://github.com/SagerNet/sing-box/releases/download/v1.8.3/sing-box-1.8.3-linux-${ARCH}.tar.gz"
tar -xzf "sing-box-1.8.3-linux-${ARCH}.tar.gz"
cp "sing-box-1.8.3-linux-${ARCH}/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 3. 配置防火墙（放行端口）
echo -e "${YELLOW}配置防火墙...${NC}"
PORTS="10000 20000 30000 40000 50000"
for port in $PORTS; do
    iptables -I INPUT -p tcp --dport $port -j ACCEPT
    iptables -I INPUT -p udp --dport $port -j ACCEPT
    echo "已放行端口: $port"
done

# 保存防火墙规则
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

# 4. 创建配置文件
echo -e "${YELLOW}生成配置文件...${NC}"
mkdir -p /etc/singbox

# 生成随机密码
SS_PASS=$(openssl rand -hex 8)
VMESS_UUID=$(cat /proc/sys/kernel/random/uuid)
TROJAN_PASS=$(openssl rand -hex 12)
SOCKS_USER="proxyuser"
SOCKS_PASS=$(openssl rand -hex 10)

# 获取公网IP
PUBLIC_IP=$(curl -s http://ipinfo.io/ip || curl -s ifconfig.me || hostname -I | awk '{print $1}')

cat > /etc/singbox/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": 10000,
      "method": "aes-128-gcm",
      "password": "${SS_PASS}",
      "network": "tcp"
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": 20000,
      "users": [
        {
          "uuid": "${VMESS_UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "tcp"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "0.0.0.0",
      "listen_port": 30000,
      "users": [
        {
          "password": "${TROJAN_PASS}"
        }
      ]
    },
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "0.0.0.0",
      "listen_port": 50000,
      "users": [
        {
          "username": "${SOCKS_USER}",
          "password": "${SOCKS_PASS}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ]
}
EOF

# 5. 创建systemd服务
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 6. 启动服务
systemctl daemon-reload
systemctl enable singbox
systemctl restart singbox

sleep 3

# 7. 检查服务状态
echo -e "${YELLOW}检查服务状态...${NC}"
if systemctl is-active --quiet singbox; then
    echo -e "${GREEN}✓ Sing-box服务运行正常${NC}"
else
    echo -e "${RED}✗ 服务启动失败，查看日志...${NC}"
    journalctl -u singbox -n 20
    exit 1
fi

# 8. 检查端口监听
echo -e "${YELLOW}检查端口监听...${NC}"
echo "监听状态:"
netstat -tlnp | grep -E '(10000|20000|30000|50000)' || echo "使用ss命令检查..."
ss -tlnp | grep -E '(10000|20000|30000|50000)' || echo "等待服务启动..."

# 9. 本地连接测试
echo -e "${YELLOW}进行本地连接测试...${NC}"
if curl -s --socks5 127.0.0.1:50000 -u ${SOCKS_USER}:${SOCKS_PASS} http://ipinfo.io/ip > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SOCKS5代理测试通过${NC}"
else
    echo -e "${RED}✗ SOCKS5代理连接失败${NC}"
fi

# 10. 生成客户端配置
echo -e "\n${GREEN}================= 客户端配置 =================${NC}"
echo "服务器IP: $PUBLIC_IP"
echo ""
echo "1. ${YELLOW}Shadowsocks (推荐)${NC}:"
echo "   地址: $PUBLIC_IP"
echo "   端口: 10000"
echo "   密码: $SS_PASS"
echo "   加密: aes-128-gcm"
echo "   链接: ss://$(echo -n "aes-128-gcm:${SS_PASS}@${PUBLIC_IP}:10000" | base64 -w 0)#Shadowsocks"
echo ""
echo "2. ${YELLOW}VMESS${NC}:"
echo "   地址: $PUBLIC_IP"
echo "   端口: 20000"
echo "   UUID: $VMESS_UUID"
echo "   额外ID: 0"
echo "   传输: TCP"
echo ""
echo "3. ${YELLOW}Trojan${NC}:"
echo "   地址: $PUBLIC_IP"
echo "   端口: 30000"
echo "   密码: $TROJAN_PASS"
echo "   链接: trojan://${TROJAN_PASS}@${PUBLIC_IP}:30000#Trojan"
echo ""
echo "4. ${YELLOW}SOCKS5${NC}:"
echo "   地址: $PUBLIC_IP"
echo "   端口: 50000"
echo "   用户名: $SOCKS_USER"
echo "   密码: $SOCKS_PASS"
echo "   链接: socks://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:50000#SOCKS5"

# 11. 生成Clash配置
cat > /root/clash-config.yaml <<EOF
port: 7890
socks-port: 7891
redir-port: 7892
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  - name: "SS-Proxy"
    type: ss
    server: ${PUBLIC_IP}
    port: 10000
    cipher: aes-128-gcm
    password: "${SS_PASS}"
    udp: true
    
  - name: "VMESS-Proxy"
    type: vmess
    server: ${PUBLIC_IP}
    port: 20000
    uuid: ${VMESS_UUID}
    alterId: 0
    cipher: auto
    
  - name: "Trojan-Proxy"
    type: trojan
    server: ${PUBLIC_IP}
    port: 30000
    password: "${TROJAN_PASS}"
    
  - name: "SOCKS5-Proxy"
    type: socks5
    server: ${PUBLIC_IP}
    port: 50000
    username: "${SOCKS_USER}"
    password: "${SOCKS_PASS}"

proxy-groups:
  - name: "🚀 代理选择"
    type: select
    proxies:
      - "SS-Proxy"
      - "VMESS-Proxy"
      - "Trojan-Proxy"
      - "DIRECT"

rules:
  - DOMAIN-SUFFIX,google.com,🚀 代理选择
  - DOMAIN-SUFFIX,github.com,🚀 代理选择
  - DOMAIN-SUFFIX,youtube.com,🚀 代理选择
  - DOMAIN-KEYWORD,spotify,🚀 代理选择
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🚀 代理选择
EOF

echo -e "\n${GREEN}Clash配置文件: /root/clash-config.yaml${NC}"

# 12. 测试命令
echo -e "\n${YELLOW}测试命令:${NC}"
echo "测试Shadowsocks: curl -x socks5://${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:50000 http://ipinfo.io/ip"
echo "查看服务状态: systemctl status singbox"
echo "查看日志: journalctl -u singbox -f"
echo "检查端口: netstat -tlnp | grep sing-box"
echo "重启服务: systemctl restart singbox"

# 13. 最终验证
echo -e "\n${YELLOW}进行最终验证...${NC}"
echo "1. 检查服务: $(systemctl is-active singbox)"
echo "2. 检查端口:"
for port in 10000 20000 30000 50000; do
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "   端口 $port: ${GREEN}开放${NC}"
    else
        echo -e "   端口 $port: ${RED}关闭${NC}"
    fi
done

echo -e "\n${GREEN}安装完成！如果无法连接，请检查:${NC}"
echo "1. 服务器防火墙是否放行端口"
echo "2. 云服务商安全组规则"
echo "3. 客户端配置是否正确"
echo "4. 运行: systemctl status singbox 查看状态"
