#!/usr/bin/env bash
set -euo pipefail

STATE_ROOT="${VAULT_LOCAL_STATE_DIR:-${HOME}/.local/state/cloud-neutral-toolkit/ai-local/vault}"
DATA_DIR="${STATE_ROOT}/data"
CONFIG_FILE="${STATE_ROOT}/vault.hcl"
LOG_FILE="${STATE_ROOT}/vault.log"
RUN_SCRIPT="${STATE_ROOT}/vault-launch.sh"
INIT_FILE="${STATE_ROOT}/vault-init.json"
ROOT_TOKEN_FILE="${STATE_ROOT}/root-token"
VAULT_ADDR="http://127.0.0.1:8200"
LAUNCHD_LABEL="ai.openclaw.vault-local"
PLIST_FILE="${HOME}/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
LAUNCHD_DOMAIN="gui/$(id -u)"

usage() {
  cat <<'EOF'
Usage: deploy/vault/scripts/run-local-macos.sh <up|down|restart|status|logs|env>
EOF
}

log() {
  printf '[vault-local] %s\n' "$*"
}

die() {
  printf '[vault-local] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

write_launch_script() {
  local vault_bin
  vault_bin="$(command -v vault)"

  mkdir -p "$STATE_ROOT"
  cat >"$RUN_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec ${vault_bin} server -config="${CONFIG_FILE}"
EOF
  chmod +x "$RUN_SCRIPT"
}

write_plist() {
  mkdir -p "$(dirname "$PLIST_FILE")"
  cat >"$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUN_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${STATE_ROOT}</string>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
}

current_pid() {
  local pid
  pid="$(launchctl print "${LAUNCHD_DOMAIN}/${LAUNCHD_LABEL}" 2>/dev/null | awk -F'= ' '/pid = / {print $2; exit}' | tr -d ';' || true)"
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi

  lsof -tiTCP:8200 -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

service_loaded() {
  launchctl print "${LAUNCHD_DOMAIN}/${LAUNCHD_LABEL}" >/dev/null 2>&1
}

is_running() {
  local pid
  pid="$(current_pid)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

write_config() {
  mkdir -p "$STATE_ROOT" "$DATA_DIR"
  cat >"$CONFIG_FILE" <<EOF
ui = true
disable_mlock = true

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

storage "raft" {
  path    = "${DATA_DIR}"
  node_id = "vault-local"
}

listener "tcp" {
  address         = "127.0.0.1:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable     = true
}
EOF
}

health_code() {
  curl -s -o /dev/null -w '%{http_code}' "${VAULT_ADDR}/v1/sys/health" || true
}

wait_for_api() {
  local code
  local try
  for try in $(seq 1 30); do
    code="$(health_code)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
    sleep 1
  done

  die "vault did not become reachable on ${VAULT_ADDR}"
}

start_server() {
  write_config
  write_launch_script
  write_plist
  : >"$LOG_FILE"

  if service_loaded; then
    launchctl kickstart -k "${LAUNCHD_DOMAIN}/${LAUNCHD_LABEL}" >/dev/null
  else
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST_FILE"
  fi

  wait_for_api
}

initialize_if_needed() {
  local code
  code="$(health_code)"
  if [[ "$code" != "501" ]]; then
    return 0
  fi

  if [[ -f "$INIT_FILE" ]]; then
    die "vault reports uninitialized but ${INIT_FILE} already exists"
  fi

  log "initializing local vault"
  VAULT_ADDR="$VAULT_ADDR" vault operator init \
    -address="$VAULT_ADDR" \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json >"$INIT_FILE"
  chmod 600 "$INIT_FILE"
  jq -r '.root_token' "$INIT_FILE" >"$ROOT_TOKEN_FILE"
  chmod 600 "$ROOT_TOKEN_FILE"
}

unseal_if_needed() {
  local code
  code="$(health_code)"
  if [[ "$code" != "503" ]]; then
    return 0
  fi

  [[ -f "$INIT_FILE" ]] || die "missing ${INIT_FILE}; cannot unseal"
  log "unsealing local vault"
  VAULT_ADDR="$VAULT_ADDR" vault operator unseal \
    -address="$VAULT_ADDR" \
    "$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")" >/dev/null
}

up() {
  require_cmd vault
  require_cmd jq
  require_cmd curl
  require_cmd launchctl

  start_server
  initialize_if_needed
  unseal_if_needed

  local code
  code="$(health_code)"
  [[ "$code" == "200" || "$code" == "429" ]] || die "unexpected health code: ${code}"

  log "listening on ${VAULT_ADDR}"
  log "root token saved at ${ROOT_TOKEN_FILE}"
}

down() {
  local pid
  pid="$(current_pid)"

  if ! service_loaded && [[ -z "$pid" ]]; then
    log "not running"
    return 0
  fi

  if service_loaded; then
    launchctl bootout "${LAUNCHD_DOMAIN}/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
  elif [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  log "stopped"
}

status() {
  if ! is_running; then
    log "not running"
    return 1
  fi

  VAULT_ADDR="$VAULT_ADDR" vault status
}

logs() {
  mkdir -p "$STATE_ROOT"
  touch "$LOG_FILE"
  tail -n 100 -f "$LOG_FILE"
}

env_cmd() {
  printf 'export VAULT_ADDR=%q\n' "$VAULT_ADDR"
  printf 'export VAULT_TOKEN="$(cat %q)"\n' "$ROOT_TOKEN_FILE"
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || {
  usage
  exit 1
}

case "$ACTION" in
  up)
    up
    ;;
  down)
    down
    ;;
  restart)
    down
    up
    ;;
  status)
    status
    ;;
  logs)
    logs
    ;;
  env)
    env_cmd
    ;;
  *)
    usage
    exit 1
    ;;
esac
