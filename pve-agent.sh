#!/usr/bin/env bash
# PVE Agent 一键部署脚本（改进版）
# 用法:
#   sudo bash pve-agent.sh [HUB_URL_or_IP] [--ws] [RELEASE_TAG]
# 示例:
#   sudo bash pve-agent.sh                 # 使用 wss://10.0.0.5:8080/push 和 release 11
#   sudo bash pve-agent.sh 10.10.10.3      # 使用 wss://10.10.10.3:8080/push
#   sudo bash pve-agent.sh ws://host:8080/push --ws 12

set -euo pipefail
IFS=$'\n\t'

# 可配置项
DEFAULT_HUB_IP="10.0.0.5"
DEFAULT_RELEASE_TAG="11"
REPO="iouyjl/x-ui"
BIN_PATH="/usr/local/bin/pve-agent"
ENV_FILE="/etc/default/pve-agent"
SERVICE_FILE="/etc/systemd/system/pve-agent.service"
SERVICE_USER="pve-agent"

# 简单的输出函数
err() { echo "ERROR: $*" >&2; }
info() { echo "==> $*"; }

if [ "${EUID:-0}" -ne 0 ]; then
  err "此脚本需以 root 运行（sudo）。"
  exit 1
fi

# 解析参数
ARG1="${1:-}"
FORCE_WS=false
RELEASE_TAG="${3:-${2:-$DEFAULT_RELEASE_TAG}}"

for a in "$@"; do
  if [ "$a" = "--ws" ]; then FORCE_WS=true; fi
done

if [ -z "$ARG1" ]; then
  HUB_IP="$DEFAULT_HUB_IP"
  SCHEME="ws"
  HUB_URL="${SCHEME}://${HUB_IP}:8080/push"
elif [[ "$ARG1" == *"://"* ]]; then
  HUB_URL="$ARG1"
else
  HUB_IP="$ARG1"
  SCHEME="ws"
  HUB_URL="${SCHEME}://${HUB_IP}:8080/push"
fi

if [ "$FORCE_WS" = true ]; then
  HUB_URL="${HUB_URL/#ws:/ws:}"
fi

info "使用 HUB URL: $HUB_URL"
info "Release tag: $RELEASE_TAG"

# 检查工具
DL_CMD=""
if command -v curl >/dev/null 2>&1; then
  DL_CMD="curl -fSL"
elif command -v wget >/dev/null 2>&1; then
  DL_CMD="wget -O -"
else
  err "未检测到 curl 或 wget。请安装其中一个后重试。"
  exit 2
fi

if ! command -v systemctl >/dev/null 2>&1; then
  err "未检测到 systemd (systemctl)。此安装脚本需要 systemd。"
  exit 3
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/pve-agent"

# 下载到临时文件并原子安装
tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

info "正在下载 $DOWNLOAD_URL ..."
if command -v curl >/dev/null 2>&1; then
  curl -fSL --retry 3 --retry-delay 2 -o "$tmpfile" "$DOWNLOAD_URL"
else
  wget -O "$tmpfile" "$DOWNLOAD_URL"
fi

if [ ! -s "$tmpfile" ]; then
  err "下载失败或文件为空。"
  exit 4
fi

install -m 0755 "$tmpfile" "$BIN_PATH"
info "已安装二进制到 $BIN_PATH"

# 创建系统用户（降权运行）
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  info "创建系统用户 $SERVICE_USER ..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" || true
fi

chown root:root "$BIN_PATH"
chmod 0755 "$BIN_PATH"

# 生成/备份配置文件
if [ -f "$ENV_FILE" ]; then
  info "备份现有配置 $ENV_FILE 到 ${ENV_FILE}.bak.$(date +%s)"
  cp -a "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
fi

cat > "$ENV_FILE" <<EOF
# PVE Agent 配置
# 修改后执行: systemctl restart pve-agent
HUB_URL="${HUB_URL}"
EOF

chmod 0644 "$ENV_FILE"

# 生成 systemd 单元（备份旧单元）
if [ -f "$SERVICE_FILE" ]; then
  info "备份现有单元 $SERVICE_FILE 到 ${SERVICE_FILE}.bak.$(date +%s)"
  cp -a "$SERVICE_FILE" "${SERVICE_FILE}.bak.$(date +%s)"
fi

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=PVE Monitor Agent
After=network.target

[Service]
EnvironmentFile=/etc/default/pve-agent
User=pve-agent
Group=pve-agent
WorkingDirectory=/var/lib/pve-agent
RuntimeDirectory=pve-agent
RuntimeDirectoryMode=0750
ExecStart=/usr/local/bin/pve-agent
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60
# 基本沙箱和安全性增强
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes
PrivateDevices=yes
# 如需更细粒度的能力，取消注释并调整如下项
# CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# 确保工作目录存在并设置权限
mkdir -p /var/lib/pve-agent
chown "$SERVICE_USER":"$SERVICE_USER" /var/lib/pve-agent
chmod 0750 /var/lib/pve-agent

info "正在 reload systemd，启用并启动服务..."
systemctl daemon-reload
systemctl enable --now pve-agent

info "✅ 部署完成"
echo "Hub 地址: $HUB_URL"
echo "配置文件: $ENV_FILE"
echo "查看状态: systemctl status pve-agent"
echo "查看日志: journalctl -u pve-agent -f"

exit 0
