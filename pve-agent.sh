#!/usr/bin/env bash
# Robust PVE Agent one‑liner installer
# Usage:
#   sudo bash pve-agent.sh [HUB_URL_or_IP] [--ws] [RELEASE_TAG]
# Examples:
#   sudo bash pve-agent.sh                 # uses wss://10.0.0.5:8080/push and release 11
#   sudo bash pve-agent.sh 10.10.10.3      # uses wss://10.10.10.3:8080/push
#   sudo bash pve-agent.sh ws://host:8080/push --ws 12

set -euo pipefail
IFS=$'\n\t'

# Defaults
DEFAULT_HUB_IP="10.0.0.5"
DEFAULT_RELEASE_TAG="11"
REPO="iouyjl/x-ui"
BIN_PATH="/usr/local/bin/pve-agent"
ENV_FILE="/etc/default/pve-agent"
SERVICE_FILE="/etc/systemd/system/pve-agent.service"
SERVICE_USER="pve-agent"

# Helpers
err() { echo "ERROR: $*" >&2; }
info() { echo "==> $*"; }

if [ "$EUID" -ne 0 ]; then
  err "This script must be run as root (sudo)."
  exit 1
fi

# Parse args
ARG1="${1:-}"
FORCE_WS=false
RELEASE_TAG="${3:-${2:-$DEFAULT_RELEASE_TAG}}"

# allow second arg to be --ws regardless of position
for a in "$@"; do
  if [ "$a" = "--ws" ]; then FORCE_WS=true; fi
done

if [ -z "$ARG1" ]; then
  HUB_IP="$DEFAULT_HUB_IP"
  SCHEME="wss"
  HUB_URL="${SCHEME}://${HUB_IP}:8080/push"
elif [[ "$ARG1" == *"://"* ]]; then
  HUB_URL="$ARG1"
else
  HUB_IP="$ARG1"
  SCHEME="wss"
  HUB_URL="${SCHEME}://${HUB_IP}:8080/push"
fi

if [ "$FORCE_WS" = true ]; then
  HUB_URL="${HUB_URL/#wss:/ws:}"
fi

info "Using HUB URL: $HUB_URL"
info "Release tag: $RELEASE_TAG"

# Check required tools
DL_CMD=""
if command -v curl >/dev/null 2>&1; then
  DL_CMD="curl -fSL"
elif command -v wget >/dev/null 2>&1; then
  DL_CMD="wget -O -"
else
  err "Neither curl nor wget was found. Install one and re-run."
  exit 2
fi

if ! command -v systemctl >/dev/null 2>&1; then
  err "systemctl not found. This installer requires systemd."
  exit 3
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/pve-agent"

# Download into a temporary file and install atomically
tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

info "Downloading $DOWNLOAD_URL ..."
if command -v curl >/dev/null 2>&1; then
  curl -fSL --retry 3 --retry-delay 2 -o "$tmpfile" "$DOWNLOAD_URL"
else
  wget -O "$tmpfile" "$DOWNLOAD_URL"
fi

# Basic sanity check
if [ ! -s "$tmpfile" ]; then
  err "Download failed or file empty."
  exit 4
fi

install -m 0755 "$tmpfile" "$BIN_PATH"
info "Installed binary to $BIN_PATH"

# Create service user if missing
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  info "Creating system user $SERVICE_USER ..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" || true
fi

# Ensure permissions allow execution by service user if necessary
chown root:root "$BIN_PATH"
chmod 0755 "$BIN_PATH"

# Create configuration file (idempotent; back up existing)
if [ -f "$ENV_FILE" ]; then
  info "Backing up existing $ENV_FILE to ${ENV_FILE}.bak.$(date +%s)"
  cp -a "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
fi

cat > "$ENV_FILE" <<EOF
# PVE Agent configuration
# Modify and restart the service: systemctl restart pve-agent
HUB_URL="${HUB_URL}"
EOF

chmod 0644 "$ENV_FILE"

# Create service unit (back up existing)
if [ -f "$SERVICE_FILE" ]; then
  info "Backing up existing $SERVICE_FILE to ${SERVICE_FILE}.bak.$(date +%s)"
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
# Basic hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes
PrivateDevices=yes
# Reduce privileges further by dropping capabilities if needed
# CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Ensure working dirs exist with correct ownership
mkdir -p /var/lib/pve-agent
chown "$SERVICE_USER":"$SERVICE_USER" /var/lib/pve-agent
chmod 0750 /var/lib/pve-agent

info "Reloading systemd, enabling and starting service ..."
systemctl daemon-reload
systemctl enable --now pve-agent

info "✅ Deployment completed"
echo "Hub address: $HUB_URL"
echo "Configuration file: $ENV_FILE"
echo "Check status: systemctl status pve-agent"
echo "Follow logs: journalctl -u pve-agent -f"

exit 0
