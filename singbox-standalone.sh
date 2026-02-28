#!/bin/bash
set -e  # 出错即退出，避免脚本继续执行

# 定义颜色输出（可选，提升可读性）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 版本和路径配置（可根据需要修改）
SINGBOX_VERSION="1.12.21"
ARCH="amd64"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
SERVICE_NAME="sing-box"

# 打印欢迎信息
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Sing-box 全自动安装脚本 (修复版)    ${NC}"
echo -e "${GREEN}=======================================${NC}"

# 1. 更新系统依赖
echo -e "${YELLOW}  更新系统依赖...${NC}"
apt update -y && apt install -y curl tar wget sudo > /dev/null 2>&1

# 2. 下载并解压 Sing-box
echo -e "${YELLOW}  下载 Sing-box v${SINGBOX_VERSION}...${NC}"
TMP_DIR="/tmp/sing-box-tmp"
mkdir -p ${TMP_DIR}
cd ${TMP_DIR}

# 下载二进制包
wget -q --no-check-certificate "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${ARCH}.tar.gz" -O singbox.tar.gz

# 解压
tar -zxf singbox.tar.gz
chmod +x sing-box-${SINGBOX_VERSION}-linux-${ARCH}/sing-box

# 移动到系统可执行目录
mv sing-box-${SINGBOX_VERSION}-linux-${ARCH}/sing-box ${INSTALL_DIR}/
if [ -f "${INSTALL_DIR}/sing-box" ]; then
    echo -e "${GREEN}  Sing-box 安装成功！${NC}"
else
    echo -e "${RED}  Sing-box 安装失败！${NC}"
    rm -rf ${TMP_DIR}
    exit 1
fi

# 清理临时文件
rm -rf ${TMP_DIR}

# 3. 生成基础配置文件
echo -e "${YELLOW}  生成基础配置文件...${NC}"
mkdir -p ${CONFIG_DIR}
cat > ${CONFIG_DIR}/config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "sing-box0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "sniff": true
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
    }
  ]
}
EOF

# 4. 创建系统服务
echo -e "${YELLOW}  创建系统服务...${NC}"
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 重载系统服务
systemctl daemon-reload
systemctl enable ${SERVICE_NAME} > /dev/null 2>&1

# 5. 关闭防火墙（兼容Debian/Ubuntu）
echo -e "${YELLOW}  关闭防火墙...${NC}"
if command -v ufw > /dev/null 2>&1; then
    ufw disable > /dev/null 2>&1 || true
fi
if command -v iptables > /dev/null 2>&1; then
    iptables -F > /dev/null 2>&1 || true
    iptables -X > /dev/null 2>&1 || true
    iptables -P INPUT ACCEPT > /dev/null 2>&1 || true
    iptables -P OUTPUT ACCEPT > /dev/null 2>&1 || true
    iptables -P FORWARD ACCEPT > /dev/null 2>&1 || true
fi

# 6. 优化网络参数
echo -e "${YELLOW}  优化网络参数...${NC}"
cat >> /etc/sysctl.conf << EOF
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
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p > /dev/null 2>&1 || true

# 7. 启动服务
echo -e "${YELLOW}  启动 Sing-box 服务...${NC}"
sleep 3
systemctl start ${SERVICE_NAME}

# 检查服务状态
if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo -e "${GREEN}=======================================${NC}"
    echo -e "${GREEN}  Sing-box 安装并启动成功！${NC}"
    echo -e "${GREEN}  配置文件路径：${CONFIG_DIR}/config.json${NC}"
    echo -e "${GREEN}  服务管理命令：${NC}"
    echo -e "    systemctl start ${SERVICE_NAME}  # 启动"
    echo -e "    systemctl stop ${SERVICE_NAME}   # 停止"
    echo -e "    systemctl status ${SERVICE_NAME} # 查看状态"
    echo -e "${GREEN}=======================================${NC}"
else
    echo -e "${RED}  Sing-box 服务启动失败！${NC}"
    echo -e "${RED}  查看日志：journalctl -u ${SERVICE_NAME} -f${NC}"
    exit 1
fi
