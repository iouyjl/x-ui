#!/bin/bash

# --- 配置区 ---
GITHUB_URL="https://ghproxy.net/https://github.com/iouyjl/x-ui/raw/refs/heads/main/pve_hw_api"
INSTALL_PATH="/usr/local/bin/pve_hw_api"
SERVICE_NAME="pve-hw-api"

# --- 检查 Root 权限 ---
if [ "$EUID" -ne 0 ]; then 
  echo "请以 root 权限运行此脚本。"
  exit 1
fi

echo "开始全自动安装 PVE 硬件采集程序..."

# 1. 安装底层硬件工具依赖
echo "正在安装依赖工具 (smartmontools, ipmitool, lm-sensors)..."
apt update -y && apt install -y smartmontools ipmitool lm-sensors

# 2. 下载二进制程序
echo "正在下载程序..."
wget -O "$INSTALL_PATH" "$GITHUB_URL"

if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络或链接是否有效。"
    exit 1
fi

# 3. 授权
chmod +x "$INSTALL_PATH"

# 4. 创建 Systemd 服务
echo "正在配置系统服务..."
cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=PVE Hardware Monitor API
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}
Restart=always
RestartSec=5
StandardOutput=append:/var/log/pve_hw_api.log
StandardError=append:/var/log/pve_hw_api.log

[Install]
WantedBy=multi-user.target
EOF

# 5. 启动服务
echo "正在启动服务..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

# 6. 完成提示
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "===================================================="
echo "✅ 安装完成！"
echo "🌐 API 访问地址: http://${IP_ADDR}:8080/hw"
echo "📄 日志文件路径: /var/log/pve_hw_api.log"
echo ""
echo "常用管理命令："
echo " - 查看状态: systemctl status ${SERVICE_NAME}"
echo " - 停止服务: systemctl stop ${SERVICE_NAME}"
echo " - 重启服务: systemctl restart ${SERVICE_NAME}"
echo "===================================================="
