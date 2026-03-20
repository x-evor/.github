#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw/local-state}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${HOME}/.openclaw/openclaw.json}"
ENV_FILE="${OPENCLAW_ENV_FILE:-${HOME}/.openclaw/.env}"
LOG_DIR="${HOME}/Library/Logs/openclaw"
LOG_FILE="${LOG_DIR}/gateway-local.log"
PORT="${OPENCLAW_LOCAL_PORT:-18789}"
URL="http://127.0.0.1:${PORT}"
LEGACY_LABEL="ai.openclaw.gateway-local"
LEGACY_PLIST="${HOME}/Library/LaunchAgents/${LEGACY_LABEL}.plist"
LAUNCHD_DOMAIN="gui/$(id -u)"

usage() {
  cat <<'EOF'
Usage: scripts/run-openclaw-local.sh <up|down|restart|status|logs|env|health>
EOF
}

log() {
  printf '[openclaw-local] %s\n' "$*"
}

die() {
  printf '[openclaw-local] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_env() {
  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  if ! grep -q '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE"; then
    require_cmd openssl
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(openssl rand -base64 32 | tr -d '\n')" >>"$ENV_FILE"
  fi
}

load_env() {
  ensure_env
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  export OPENCLAW_STATE_DIR="$STATE_DIR"
  export OPENCLAW_CONFIG_PATH="$CONFIG_PATH"
  export OPENCLAW_GATEWAY_MODE="local"
}

ensure_config() {
  mkdir -p "$(dirname "$CONFIG_PATH")" "$STATE_DIR" "${STATE_DIR}/workspace"

  if [[ ! -f "$CONFIG_PATH" ]]; then
    cat >"$CONFIG_PATH" <<EOF
{
  "gateway": {
    "port": ${PORT},
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "allowedOrigins": [
        "https://openclaw.svc.plus",
        "http://127.0.0.1:${PORT}",
        "http://localhost:${PORT}"
      ]
    }
  }
}
EOF
    return 0
  fi

  require_cmd jq
  local tmp
  tmp="$(mktemp)"
  jq --argjson port "$PORT" '
    .gateway = (.gateway // {}) |
    .gateway.port = $port |
    .gateway.mode = "local" |
    .gateway.bind = "loopback" |
    .gateway.auth = (.gateway.auth // {}) |
    .gateway.auth.mode = "token" |
    .gateway.controlUi = (.gateway.controlUi // {}) |
    .gateway.controlUi.allowedOrigins = [
      "https://openclaw.svc.plus",
      ("http://127.0.0.1:" + ($port | tostring)),
      ("http://localhost:" + ($port | tostring))
    ]
  ' "$CONFIG_PATH" >"$tmp"
  install -m 0644 "$tmp" "$CONFIG_PATH"
  rm -f "$tmp"
}

cleanup_legacy_service() {
  launchctl bootout "${LAUNCHD_DOMAIN}/${LEGACY_LABEL}" >/dev/null 2>&1 || true
  rm -f "$LEGACY_PLIST"
}

current_pid() {
  lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

health() {
  curl -fsS "${URL}/health" >/dev/null
}

wait_for_health() {
  local try
  for try in $(seq 1 30); do
    if health; then
      return 0
    fi
    sleep 1
  done

  die "openclaw did not become healthy on ${URL}"
}

up() {
  require_cmd openclaw
  require_cmd curl
  require_cmd jq
  require_cmd launchctl

  mkdir -p "$LOG_DIR"
  : >"$LOG_FILE"

  cleanup_legacy_service
  ensure_config
  load_env

  openclaw gateway install --force --port "$PORT" --token "$OPENCLAW_GATEWAY_TOKEN" >/dev/null
  openclaw gateway start >/dev/null
  wait_for_health
  log "listening on ${URL}"
}

down() {
  require_cmd openclaw
  cleanup_legacy_service
  openclaw gateway stop >/dev/null 2>&1 || true

  local pid
  pid="$(current_pid)"
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  log "stopped"
}

status() {
  require_cmd openclaw
  openclaw gateway status --json
}

logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  tail -n 100 -f "$LOG_FILE"
}

env_cmd() {
  printf 'export OPENCLAW_STATE_DIR=%q\n' "$STATE_DIR"
  printf 'export OPENCLAW_CONFIG_PATH=%q\n' "$CONFIG_PATH"
  printf 'export OPENCLAW_GATEWAY_TOKEN="$(grep -E %q %q | cut -d= -f2-)"\n' '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE"
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
  health)
    health
    ;;
  *)
    usage
    exit 1
    ;;
esac
