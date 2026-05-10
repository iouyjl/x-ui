#!/bin/bash
GITHUB_URL="https://ghproxy.net/https://github.com/iouyjl/x-ui/raw/main/pve_hw_api"
INSTALL_PATH="/usr/local/bin/pve_hw_api"
SERVICE_NAME="pve-hw-api"

if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行"
  exit 1
fi

echo "开始安装 PVE 硬件采集 API"
apt update -y
apt install -y smartmontools ipmitool lm-sensors

wget -O "$INSTALL_PATH" "$GITHUB_URL"
chmod +x "$INSTALL_PATH"

cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=PVE Hardware API
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $SERVICE_NAME

IP=$(hostname -I | awk '{print $1}')
echo "安装完成！访问地址：http://$IP:8080/hw"
