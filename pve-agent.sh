#!/bin/bash
# PVE Agent 一键部署脚本
# 用法: bash install.sh [HubIP]
# 示例: bash install.sh 10.10.10.3

HUB_IP="${1:-10.0.0.5}"
HUB_URL="ws://${HUB_IP}:8080/push"

# 下载二进制
wget -O /usr/local/bin/pve-agent https://github.com/iouyjl/x-ui/releases/download/11/pve-agent
chmod +x /usr/local/bin/pve-agent

# 创建配置文件
cat <<EOF > /etc/default/pve-agent
# PVE Agent 配置
# 修改后执行 systemctl restart pve-agent 生效
HUB_URL=$HUB_URL
EOF

# 创建 Systemd 服务文件
cat <<EOF > /etc/systemd/system/pve-agent.service
[Unit]
Description=PVE Monitor Agent
After=network.target

[Service]
EnvironmentFile=/etc/default/pve-agent
ExecStart=/usr/local/bin/pve-agent
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable pve-agent
systemctl start pve-agent

echo "✅ 部署完成"
echo "Hub地址: $HUB_URL"
echo "配置文件: /etc/default/pve-agent"
echo "查看状态: systemctl status pve-agent"
echo "查看日志: journalctl -u pve-agent -f"
