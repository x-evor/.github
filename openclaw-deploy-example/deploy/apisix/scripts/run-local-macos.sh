#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="${ROOT_DIR}/example/vps"
ENV_FILE="${ROOT_DIR}/macos/.env.local"
RULES_FILE="${BASE_DIR}/conf/apisix.yaml"
CONFIG_FILE="${BASE_DIR}/conf/config.yaml"

APISIX_HOME="${APISIX_LOCAL_SRC_DIR:-${HOME}/.local/src/apisix}"
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-${HOME}/.local/openresty}"
LUA_RESTY_EVENTS_HOME="${LUA_RESTY_EVENTS_HOME:-${HOME}/.local/src/lua-resty-events}"
APISIX_PROFILE="${APISIX_PROFILE:-local}"

APISIX_BIN="${APISIX_HOME}/bin/apisix"
OPENRESTY_BIN="${OPENRESTY_PREFIX}/bin/openresty"
APISIX_LOG_DIR="${APISIX_HOME}/logs"
APISIX_PORT=9080

usage() {
  cat <<'EOF'
Usage: deploy/apisix/scripts/run-local-macos.sh <validate|up|down|restart|status|logs|smoke>

Environment overrides:
  APISIX_LOCAL_SRC_DIR   Local APISIX source/runtime tree (default: ~/.local/src/apisix)
  OPENRESTY_PREFIX       Local OpenResty prefix (default: ~/.local/openresty)
  LUA_RESTY_EVENTS_HOME  Local lua-resty-events clone path
EOF
}

log() {
  printf '[apisix-local] %s\n' "$*"
}

die() {
  printf '[apisix-local] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

load_env() {
  require_file "$ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  export API_PUBLIC_HOST="${API_PUBLIC_HOST:-api.svc.plus}"
  export LOCAL_API_HOST="${LOCAL_API_HOST:-127.0.0.1}"
  export APISIX_PROFILE
  export PATH="${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/nginx/sbin:${PATH}"
}

ensure_runtime_links() {
  mkdir -p "${APISIX_HOME}/conf" "$APISIX_LOG_DIR"
  ln -snf "$CONFIG_FILE" "${APISIX_HOME}/conf/config-${APISIX_PROFILE}.yaml"
  ln -snf "$RULES_FILE" "${APISIX_HOME}/conf/apisix-${APISIX_PROFILE}.yaml"
}

ensure_lua_resty_events() {
  if [[ -f "${OPENRESTY_PREFIX}/lualib/resty/events/compat/init.lua" ]]; then
    return 0
  fi

  require_cmd git
  require_cmd make

  if [[ ! -d "${LUA_RESTY_EVENTS_HOME}/.git" ]]; then
    log "cloning lua-resty-events into ${LUA_RESTY_EVENTS_HOME}"
    git clone --depth 1 https://github.com/Kong/lua-resty-events.git "$LUA_RESTY_EVENTS_HOME"
  fi

  log "installing lua-resty-events into ${OPENRESTY_PREFIX}/lualib"
  (
    cd "$LUA_RESTY_EVENTS_HOME"
    make install LUA_LIB_DIR="${OPENRESTY_PREFIX}/lualib"
  )

  if [[ -f "${OPENRESTY_PREFIX}/lualib/resty/events/worker.lua" ]]; then
    perl -0pi -e 's/log\(ERR, "event worker failed: ", perr\)/log(ngx.WARN, "event worker failed: ", perr)/' \
      "${OPENRESTY_PREFIX}/lualib/resty/events/worker.lua"
  fi
}

validate() {
  require_cmd curl
  require_file "$ENV_FILE"
  require_file "$RULES_FILE"
  require_file "$CONFIG_FILE"
  [[ -x "$OPENRESTY_BIN" ]] || die "missing OpenResty binary: ${OPENRESTY_BIN}"
  [[ -x "$APISIX_BIN" ]] || die "missing APISIX CLI: ${APISIX_BIN}"

  "${OPENRESTY_BIN}" -V 2>&1 | grep -q -- '--with-http_stub_status_module' || {
    die "OpenResty at ${OPENRESTY_BIN} must be built with --with-http_stub_status_module"
  }

  tail -n 1 "$RULES_FILE" | grep -q '^#END$' || {
    die "conf/apisix.yaml must end with #END for standalone reloads"
  }

  ensure_lua_resty_events
  ensure_runtime_links
  load_env

  (
    cd "$APISIX_HOME"
    "$APISIX_BIN" test >/dev/null
  )

  log "validation passed"
}

smoke() {
  load_env
  curl -fsS \
    -H "Authorization: Bearer ${AI_GATEWAY_ACCESS_TOKEN}" \
    "http://127.0.0.1:${APISIX_PORT}/v1/models" >/dev/null
  log "smoke ok: http://127.0.0.1:${APISIX_PORT}/v1/models"
}

is_running() {
  lsof -nP -iTCP:${APISIX_PORT} -sTCP:LISTEN >/dev/null 2>&1
}

up() {
  validate
  if is_running && smoke >/dev/null 2>&1; then
    log "already listening on http://127.0.0.1:${APISIX_PORT}"
    return 0
  fi
  (
    cd "$APISIX_HOME"
    "$APISIX_BIN" start
  )
  sleep 2
  smoke
  log "listening on http://127.0.0.1:${APISIX_PORT}"
}

down() {
  if [[ ! -x "$APISIX_BIN" ]]; then
    die "missing APISIX CLI: ${APISIX_BIN}"
  fi

  if [[ -f "$ENV_FILE" ]]; then
    load_env
  else
    export APISIX_PROFILE
    export PATH="${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/nginx/sbin:${PATH}"
  fi

  (
    cd "$APISIX_HOME"
    "$APISIX_BIN" stop || true
  )
  log "stopped"
}

status() {
  if lsof -nP -iTCP:${APISIX_PORT} -sTCP:LISTEN >/dev/null 2>&1; then
    log "port ${APISIX_PORT} is listening"
    lsof -nP -iTCP:${APISIX_PORT} -sTCP:LISTEN
    if [[ -f "$ENV_FILE" ]]; then
      smoke || true
    fi
  else
    log "port ${APISIX_PORT} is not listening"
    return 1
  fi
}

logs() {
  mkdir -p "$APISIX_LOG_DIR"
  tail -n 100 -f "${APISIX_LOG_DIR}/error.log" "${APISIX_LOG_DIR}/access.log"
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || {
  usage
  exit 1
}

case "$ACTION" in
  validate)
    validate
    ;;
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
  smoke)
    smoke
    ;;
  *)
    usage
    exit 1
    ;;
esac
