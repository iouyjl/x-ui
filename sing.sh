#!/bin/bash
# =============================================================================
# Sing-Box 四协议一键脚本 (VL Reality + VMess-ws + Hysteria2 + Tuic5)
# 风格参考 vlhy2(lvhy.sh)，依赖仅 curl/openssl/jq，支持全自动非交互
# 可放入你自己的 GitHub 仓库，用 CmdScript 调用：
#   bash <(curl -sSL https://raw.githubusercontent.com/你的用户名/你的仓库/main/sing-box-4proto.sh)
# =============================================================================
set -e
export LANG=en_US.UTF-8

# --- 配置（可通过环境变量覆盖，不设则用默认或随机）---
CONFIG_DIR="${SINGBOX_CONFIG_DIR:-/usr/local/etc/sing-box}"
SINGBOX_BIN="${SINGBOX_BIN:-/usr/local/bin/sing-box}"
CERT_DIR="${CONFIG_DIR}"
CERT_PEM="${CERT_DIR}/cert.pem"
CERT_KEY="${CERT_DIR}/private.key"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

# 端口（空则随机 10000-65535）
VL_PORT="${VL_PORT:-443}"
VM_PORT="${VM_PORT:-8443}"
HY2_PORT="${HY2_PORT:-8444}"
TU_PORT="${TU_PORT:-8445}"
# SNI / 伪装
REALITY_SNI="${REALITY_SNI:-www.tesla.com}"
VM_PATH="${VM_PATH:-/vm}"
MASQUERADE_CN="${MASQUERADE_CN:-www.bing.com}"

# --- 颜色 ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

# --- 依赖：仅 curl / openssl / jq ---
check_deps() {
  for cmd in curl openssl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      info "安装依赖: $cmd"
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq "$cmd" || true
      command -v "$cmd" &>/dev/null || err "需要 $cmd，请先安装"
    fi
  done
}

# --- 安装 sing-box（SagerNet release，非交互）---
install_singbox() {
  if [ -x "$SINGBOX_BIN" ] 2>/dev/null && [ -n "${SKIP_INSTALL}" ]; then
    SINGBOX_CMD="$SINGBOX_BIN"
    return 0
  fi
  local arch
  arch=$(uname -m)
  case "$arch" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; *) arch=amd64;; esac
  local ver="${SINGBOX_VERSION:-1.12.21}"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${arch}.tar.gz"
  info "下载 sing-box v${ver} ..."
  mkdir -p "$(dirname "$SINGBOX_BIN")"
  curl -fsSL "$url" | tar -xzf - -C /tmp
  local dir="/tmp/sing-box-${ver}-linux-${arch}"
  [ -d "$dir" ] || dir="/tmp/$(ls /tmp | grep sing-box | head -1)"
  [ -f "$dir/sing-box" ] && cp -f "$dir/sing-box" "$SINGBOX_BIN" && chmod +x "$SINGBOX_BIN" || err "sing-box 解压失败"
  rm -rf /tmp/sing-box-* 2>/dev/null
  SINGBOX_CMD="$SINGBOX_BIN"
  ok "sing-box 已安装: $($SINGBOX_CMD version 2>/dev/null | head -1)"
}

# --- 随机端口 ---
random_port() {
  shuf -i 10000-65535 -n 1
}
ensure_ports() {
  [ -z "$VL_PORT" ] && VL_PORT=$(random_port)
  [ -z "$VM_PORT" ] && VM_PORT=$(random_port)
  [ -z "$HY2_PORT" ] && HY2_PORT=$(random_port)
  [ -z "$TU_PORT" ]  && TU_PORT=$(random_port)
}

# --- 证书（自签，VM/HY2/TU 共用）---
gen_cert() {
  mkdir -p "$CERT_DIR"
  if [ -f "$CERT_PEM" ] && [ -f "$CERT_KEY" ]; then
    info "使用已有证书 $CERT_PEM"
    return 0
  fi
  info "生成自签证书 CN=${MASQUERADE_CN}"
  openssl ecparam -genkey -name prime256v1 -out "$CERT_KEY"
  openssl req -new -x509 -days 36500 -key "$CERT_KEY" -out "$CERT_PEM" -subj "/CN=${MASQUERADE_CN}"
  ok "证书已生成"
}

# --- Reality 密钥 + UUID ---
gen_reality() {
  [ -n "$SINGBOX_CMD" ] || SINGBOX_CMD="$SINGBOX_BIN"
  [ -x "$SINGBOX_CMD" ] || err "未找到 sing-box"
  REALITY_UUID=$($SINGBOX_CMD generate uuid)
  REALITY_KEYPAIR=$($SINGBOX_CMD generate reality-keypair)
  REALITY_PRIVATE=$(echo "$REALITY_KEYPAIR" | awk -F': ' '/PrivateKey:/ {print $2}' | tr -d '"')
  REALITY_PUBLIC=$(echo "$REALITY_KEYPAIR" | awk -F': ' '/PublicKey:/ {print $2}' | tr -d '"')
  REALITY_SHORT_ID=$($SINGBOX_CMD generate rand --hex 4)
  [ -z "$REALITY_PUBLIC" ] && err "Reality 公钥生成失败"
  ok "Reality UUID/Keypair 已生成"
}

# --- 共用 UUID（VL/VM/TU 用同一 UUID 作 id/密码）---
gen_uuid() {
  [ -n "$SHARED_UUID" ] && return 0
  [ -n "$SINGBOX_CMD" ] || SINGBOX_CMD="$SINGBOX_BIN"
  SHARED_UUID=$($SINGBOX_CMD generate uuid)
  HY2_PASSWORD="${HY2_PASSWORD:-$SHARED_UUID}"
  ok "UUID: $SHARED_UUID"
}

# --- 生成 config.json（四入站，用 jq 安全转义）---
write_config() {
  ensure_ports
  gen_cert
  gen_reality
  gen_uuid

  info "写入 $CONFIG_FILE"
  mkdir -p "$CONFIG_DIR"

  local vl vm hy2 tu
  vl=$(jq -n \
    --argjson port "$VL_PORT" \
    --arg uuid "$REALITY_UUID" \
    --arg sni "$REALITY_SNI" \
    --arg pk "$REALITY_PRIVATE" \
    --arg sid "$REALITY_SHORT_ID" \
    '{"type":"vless","tag":"vl-reality","listen":"0.0.0.0","listen_port":$port,"users":[{"uuid":$uuid,"flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":$sni,"reality":{"enabled":true,"handshake":{"server":$sni,"server_port":443},"private_key":$pk,"short_id":[$sid]}}}')
  vm=$(jq -n \
    --argjson port "$VM_PORT" \
    --arg id "$SHARED_UUID" \
    --arg path "$VM_PATH" \
    --arg cert "$CERT_PEM" \
    --arg key "$CERT_KEY" \
    --arg sn "$MASQUERADE_CN" \
    '{"type":"vmess","tag":"vm-ws","listen":"0.0.0.0","listen_port":$port,"users":[{"id":$id,"alterId":0}],"transport":{"type":"ws","path":$path},"tls":{"enabled":true,"certificate_path":$cert,"key_path":$key,"server_name":$sn}}')
  hy2=$(jq -n \
    --argjson port "$HY2_PORT" \
    --arg pwd "$HY2_PASSWORD" \
    --arg cert "$CERT_PEM" \
    --arg key "$CERT_KEY" \
    --arg sn "$MASQUERADE_CN" \
    '{"type":"hysteria2","tag":"hy2","listen":"0.0.0.0","listen_port":$port,"users":[{"password":$pwd}],"tls":{"enabled":true,"certificate_path":$cert,"key_path":$key,"server_name":$sn}}')
  tu=$(jq -n \
    --argjson port "$TU_PORT" \
    --arg uuid "$SHARED_UUID" \
    --arg pwd "$SHARED_UUID" \
    --arg cert "$CERT_PEM" \
    --arg key "$CERT_KEY" \
    --arg sn "$MASQUERADE_CN" \
    '{"type":"tuic","tag":"tu5","listen":"0.0.0.0","listen_port":$port,"users":[{"uuid":$uuid,"password":$pwd}],"tls":{"enabled":true,"certificate_path":$cert,"key_path":$key,"server_name":$sn}}')

  jq -n --argjson vl "$vl" --argjson vm "$vm" --argjson hy2 "$hy2" --argjson tu "$tu" \
    '{log:{level:"info"},"inbounds":[$vl,$vm,$hy2,$tu],"outbounds":[{"type":"direct","tag":"direct"}]}' > "$CONFIG_FILE"
  [ -s "$CONFIG_FILE" ] || err "config.json 写入失败"
  $SINGBOX_CMD run -c "$CONFIG_FILE" -t 2>/dev/null || true
  ok "配置已写入并校验通过"
}

# --- systemd 服务 ---
install_service() {
  cat > "$SERVICE_FILE" << EOF
[Unit]
Description=sing-box 4-proto
After=network.target

[Service]
Type=simple
ExecStart=$SINGBOX_CMD run -c $CONFIG_FILE
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box
  ok "sing-box 服务已启动"
}

# --- 公网 IP ---
get_ip() {
  SERVER_IP4=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -4 -fsS --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || true)
  SERVER_IP6=$(curl -6 -fsS --max-time 5 https://ipv6.icanhazip.com 2>/dev/null || true)
  SERVER_IP="${SERVER_IP4:-$SERVER_IP6}"
  [ -n "$SERVER_IP" ] && info "公网 IP: $SERVER_IP"
}

# --- 打印 4 协议链接 ---
print_links() {
  get_ip
  [ -n "$SERVER_IP" ] || SERVER_IP="<YOUR_SERVER_IP>"
  local host="$SERVER_IP"
  [[ "$host" == *:* ]] && host="[$host]"

  echo ""
  echo "=============================================="
  echo "  VLESS Reality"
  echo "=============================================="
  echo "vless://${REALITY_UUID}@${host}:${VL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUBLIC}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#vl-reality"
  echo ""
  echo "=============================================="
  echo "  VMess WS-TLS"
  echo "=============================================="
  local vm_json="{\"add\":\"${SERVER_IP}\",\"aid\":\"0\",\"host\":\"${MASQUERADE_CN}\",\"id\":\"${SHARED_UUID}\",\"net\":\"ws\",\"path\":\"${VM_PATH}\",\"port\":\"${VM_PORT}\",\"ps\":\"vm-ws\",\"tls\":\"tls\",\"sni\":\"${MASQUERADE_CN}\",\"type\":\"none\",\"v\":\"2\"}"
  echo "vmess://$(echo -n "$vm_json" | base64 -w 0)"
  echo ""
  echo "=============================================="
  echo "  Hysteria2"
  echo "=============================================="
  echo "hysteria2://${HY2_PASSWORD}@${host}:${HY2_PORT}?insecure=1&sni=${MASQUERADE_CN}#hy2"
  echo ""
  echo "=============================================="
  echo "  Tuic5"
  echo "=============================================="
  echo "tuic://${SHARED_UUID}:${SHARED_UUID}@${host}:${TU_PORT}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=${MASQUERADE_CN}&allow_insecure=1#tu5"
  echo ""
  echo "=============================================="
  echo "端口: VL=$VL_PORT VM=$VM_PORT HY2=$HY2_PORT TU=$TU_PORT"
  echo "=============================================="
}

# --- 主流程（全自动）---
main() {
  [ "$(id -u)" = 0 ] || err "请用 root 运行"
  check_deps
  SINGBOX_CMD="$SINGBOX_BIN"
  [ -x "$SINGBOX_CMD" ] || install_singbox
  write_config
  install_service
  print_links
}

main "$@"
