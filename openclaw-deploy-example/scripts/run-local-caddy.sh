#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE_DIR="${ROOT_DIR}/deploy/caddy/macos"
ROOT_ENV_FILE="${ROOT_DIR}/.env"
ENV_FILE="${EDGE_DIR}/.env.local"
CADDYFILE="${EDGE_DIR}/Caddyfile"
CADDYFILE_DNS="${EDGE_DIR}/Caddyfile.dns"

STATE_DIR="${HOME}/.local/state/cloud-neutral-toolkit/ai-local/caddy"
LOG_FILE="${STATE_DIR}/caddy.log"
RUN_SCRIPT="${STATE_DIR}/caddy-launch.sh"
PLIST_LABEL="ai.openclaw.caddy-local-edge"
PLIST_FILE="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
LAUNCHD_DOMAIN="gui/$(id -u)"

CADDY_BIN="${CADDY_BIN:-${HOME}/.local/bin/caddy-cloudflare}"
CADDY_BUILD_STRATEGY="${CADDY_BUILD_STRATEGY:-auto}"

usage() {
  cat <<'EOF'
Usage: scripts/run-local-caddy.sh <build|validate|up|down|restart|status|logs|verify|hosts-print|dns-status>
EOF
}

log() {
  printf '[caddy-local] %s\n' "$*"
}

die() {
  printf '[caddy-local] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

read_root_env_value() {
  local key="$1"
  [[ -f "$ROOT_ENV_FILE" ]] || return 0
  local line
  line="$(/usr/bin/grep -m1 "^${key}=" "$ROOT_ENV_FILE" 2>/dev/null || true)"
  printf '%s' "${line#*=}"
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"
  local shell_caddy_acme_email="${CADDY_ACME_EMAIL-}"
  local shell_cloudflare_api_token="${CLOUDFLARE_API_TOKEN-}"
  local shell_local_edge_http_port="${LOCAL_EDGE_HTTP_PORT-}"
  local shell_local_edge_https_port="${LOCAL_EDGE_HTTPS_PORT-}"
  local shell_caddy_admin_port="${CADDY_ADMIN_PORT-}"
  local shell_caddy_tls_mode="${CADDY_TLS_MODE-}"
  local shell_dns_resolver="${DNS_RESOLVER-}"
  local shell_ai_remote_upstream_hostport="${AI_REMOTE_UPSTREAM_HOSTPORT-}"
  local shell_ai_remote_server_name="${AI_REMOTE_SERVER_NAME-}"
  local shell_ai_upstream_host="${AI_UPSTREAM_HOST-}"
  local shell_vault_remote_server_name="${VAULT_REMOTE_SERVER_NAME-}"
  local shell_openclaw_remote_server_name="${OPENCLAW_REMOTE_SERVER_NAME-}"
  local root_caddy_acme_email=""
  local root_cloudflare_api_token=""
  local env_caddy_acme_email=""
  local env_cloudflare_api_token=""
  local git_email=""

  root_caddy_acme_email="$(read_root_env_value CADDY_ACME_EMAIL)"
  root_cloudflare_api_token="$(read_root_env_value CLOUDFLARE_API_TOKEN)"

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  env_caddy_acme_email="${CADDY_ACME_EMAIL-}"
  env_cloudflare_api_token="${CLOUDFLARE_API_TOKEN-}"

  if command -v git >/dev/null 2>&1; then
    git_email="$(git -C "$ROOT_DIR" config --get user.email 2>/dev/null || git config --get user.email 2>/dev/null || true)"
  fi

  if [[ -z "$env_caddy_acme_email" || "$env_caddy_acme_email" == "you@example.com" ]]; then
    env_caddy_acme_email="$root_caddy_acme_email"
  fi
  export CADDY_ACME_EMAIL="${shell_caddy_acme_email:-${env_caddy_acme_email:-}}"
  if [[ -z "${CADDY_ACME_EMAIL}" || "${CADDY_ACME_EMAIL}" == "you@example.com" ]]; then
    export CADDY_ACME_EMAIL="${git_email}"
  fi

  if [[ -z "$env_cloudflare_api_token" || "$env_cloudflare_api_token" == "replace-me" ]]; then
    env_cloudflare_api_token="$root_cloudflare_api_token"
  fi
  export CLOUDFLARE_API_TOKEN="${shell_cloudflare_api_token:-${env_cloudflare_api_token:-}}"
  if [[ "${CLOUDFLARE_API_TOKEN:-}" == "replace-me" ]]; then
    unset CLOUDFLARE_API_TOKEN
  fi

  export LOCAL_EDGE_HTTP_PORT="${LOCAL_EDGE_HTTP_PORT:-8080}"
  export LOCAL_EDGE_HTTP_PORT="${shell_local_edge_http_port:-${LOCAL_EDGE_HTTP_PORT}}"
  export LOCAL_EDGE_HTTPS_PORT="${LOCAL_EDGE_HTTPS_PORT:-8443}"
  export LOCAL_EDGE_HTTPS_PORT="${shell_local_edge_https_port:-${LOCAL_EDGE_HTTPS_PORT}}"
  export CADDY_ADMIN_PORT="${CADDY_ADMIN_PORT:-2019}"
  export CADDY_ADMIN_PORT="${shell_caddy_admin_port:-${CADDY_ADMIN_PORT}}"
  export CADDY_TLS_MODE="${CADDY_TLS_MODE:-internal}"
  export CADDY_TLS_MODE="${shell_caddy_tls_mode:-${CADDY_TLS_MODE}}"
  export DNS_RESOLVER="${DNS_RESOLVER:-1.1.1.1}"
  export DNS_RESOLVER="${shell_dns_resolver:-${DNS_RESOLVER}}"
  export AI_REMOTE_UPSTREAM_HOSTPORT="${AI_REMOTE_UPSTREAM_HOSTPORT:-api.svc.plus:443}"
  export AI_REMOTE_UPSTREAM_HOSTPORT="${shell_ai_remote_upstream_hostport:-${AI_REMOTE_UPSTREAM_HOSTPORT}}"
  export AI_REMOTE_SERVER_NAME="${AI_REMOTE_SERVER_NAME:-api.svc.plus}"
  export AI_REMOTE_SERVER_NAME="${shell_ai_remote_server_name:-${AI_REMOTE_SERVER_NAME}}"
  export AI_UPSTREAM_HOST="${AI_UPSTREAM_HOST:-api.svc.plus}"
  export AI_UPSTREAM_HOST="${shell_ai_upstream_host:-${AI_UPSTREAM_HOST}}"
  export VAULT_REMOTE_SERVER_NAME="${VAULT_REMOTE_SERVER_NAME:-vault.svc.plus}"
  export VAULT_REMOTE_SERVER_NAME="${shell_vault_remote_server_name:-${VAULT_REMOTE_SERVER_NAME}}"
  export OPENCLAW_REMOTE_SERVER_NAME="${OPENCLAW_REMOTE_SERVER_NAME:-openclaw.svc.plus}"
  export OPENCLAW_REMOTE_SERVER_NAME="${shell_openclaw_remote_server_name:-${OPENCLAW_REMOTE_SERVER_NAME}}"
}

select_caddyfile() {
  case "${CADDY_TLS_MODE}" in
    internal)
      ACTIVE_CADDYFILE="${CADDYFILE}"
      ;;
    dns)
      ACTIVE_CADDYFILE="${CADDYFILE_DNS}"
      ;;
    *)
      die "unsupported CADDY_TLS_MODE: ${CADDY_TLS_MODE} (expected internal or dns)"
      ;;
  esac

  [[ -f "$ACTIVE_CADDYFILE" ]] || die "missing Caddyfile for mode ${CADDY_TLS_MODE}: ${ACTIVE_CADDYFILE}"
}

ensure_ports() {
  if (( LOCAL_EDGE_HTTP_PORT < 1024 || LOCAL_EDGE_HTTPS_PORT < 1024 )) && [[ "$(id -u)" != "0" ]]; then
    die "ports ${LOCAL_EDGE_HTTP_PORT}/${LOCAL_EDGE_HTTPS_PORT} require root on macOS; use 8080/8443 or run outside this workflow with root privileges"
  fi
}

ensure_binary() {
  if [[ -x "$CADDY_BIN" ]] && "$CADDY_BIN" list-modules | grep -q '^dns.providers.cloudflare$'; then
    return 0
  fi

  mkdir -p "$(dirname "$CADDY_BIN")"

  if [[ "$CADDY_BUILD_STRATEGY" != "build" ]] && download_binary; then
    if "$CADDY_BIN" list-modules | grep -q '^dns.providers.cloudflare$'; then
      return 0
    fi
    rm -f "$CADDY_BIN"
    log "downloaded Caddy binary is missing dns.providers.cloudflare; falling back to local xcaddy build"
  fi

  if ! command -v xcaddy >/dev/null 2>&1; then
    require_cmd go
    GOBIN="${HOME}/.local/bin" go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    export PATH="${HOME}/.local/bin:${PATH}"
  fi

  [[ "$CADDY_BUILD_STRATEGY" != "download" ]] || die "download strategy requested but official custom download failed"

  local version
  local build_tmp
  if command -v caddy >/dev/null 2>&1; then
    version="$(caddy version | awk '{print $1}')"
  else
    version="v2.10.2"
  fi

  build_tmp="$(mktemp -d "${TMPDIR:-/tmp}/caddy-build.XXXXXX")"
  log "building ${CADDY_BIN} with Cloudflare DNS module"
  if ! (
    cd "$build_tmp"
    xcaddy build "$version" \
      --output "$CADDY_BIN" \
      --with github.com/caddy-dns/cloudflare
  ); then
    rm -rf "$build_tmp"
    die "failed to build custom Caddy with Cloudflare DNS module"
  fi
  rm -rf "$build_tmp"
}

download_binary() {
  require_cmd curl

  local os="darwin"
  local arch
  local tmp_bin
  local url

  case "$(uname -m)" in
    arm64|aarch64)
      arch="arm64"
      ;;
    x86_64)
      arch="amd64"
      ;;
    *)
      log "unsupported macOS architecture for download shortcut: $(uname -m)"
      return 1
      ;;
  esac

  url="https://caddyserver.com/api/download?os=${os}&arch=${arch}&p=github.com/caddy-dns/cloudflare&idempotency=$(date +%s)"
  log "downloading custom Caddy binary from ${url}"
  tmp_bin="$(mktemp "${TMPDIR:-/tmp}/caddy-download.XXXXXX")"
  if ! curl -fL --retry 3 --retry-all-errors --retry-delay 1 "$url" -o "$tmp_bin"; then
    rm -f "$tmp_bin"
    return 1
  fi
  mv "$tmp_bin" "$CADDY_BIN"
  chmod +x "$CADDY_BIN"
}

resolve_public_ip() {
  local host="$1"
  dig @"${DNS_RESOLVER}" +short "$host" A | head -n 1
}

render_runtime_exports() {
  local vault_ip
  local openclaw_ip

  vault_ip="$(resolve_public_ip "${VAULT_REMOTE_SERVER_NAME}")"
  openclaw_ip="$(resolve_public_ip "${OPENCLAW_REMOTE_SERVER_NAME}")"

  [[ -n "$vault_ip" ]] || die "failed to resolve ${VAULT_REMOTE_SERVER_NAME} via ${DNS_RESOLVER}"
  [[ -n "$openclaw_ip" ]] || die "failed to resolve ${OPENCLAW_REMOTE_SERVER_NAME} via ${DNS_RESOLVER}"

  export VAULT_REMOTE_UPSTREAM_HOSTPORT="${vault_ip}:443"
  export OPENCLAW_REMOTE_UPSTREAM_HOSTPORT="${openclaw_ip}:443"
}

write_launch_script() {
  mkdir -p "$STATE_DIR"
  cat >"$RUN_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
root_cloudflare_api_token=""
if [[ -f "${ROOT_ENV_FILE}" ]]; then
  root_cloudflare_api_token="\$(/usr/bin/grep -m1 '^CLOUDFLARE_API_TOKEN=' "${ROOT_ENV_FILE}" 2>/dev/null | cut -d= -f2- || true)"
fi
set -a
. "${ENV_FILE}"
set +a
if [[ -z "\${CLOUDFLARE_API_TOKEN:-}" || "\${CLOUDFLARE_API_TOKEN}" == "replace-me" ]]; then
  export CLOUDFLARE_API_TOKEN="\${root_cloudflare_api_token}"
fi
export CADDY_ACME_EMAIL="${CADDY_ACME_EMAIL}"
export CADDY_TLS_MODE="${CADDY_TLS_MODE}"
export LOCAL_EDGE_HTTP_PORT="${LOCAL_EDGE_HTTP_PORT}"
export LOCAL_EDGE_HTTPS_PORT="${LOCAL_EDGE_HTTPS_PORT}"
export CADDY_ADMIN_PORT="${CADDY_ADMIN_PORT}"
export DNS_RESOLVER="${DNS_RESOLVER}"
export AI_REMOTE_UPSTREAM_HOSTPORT="${AI_REMOTE_UPSTREAM_HOSTPORT}"
export AI_REMOTE_SERVER_NAME="${AI_REMOTE_SERVER_NAME}"
export AI_UPSTREAM_HOST="${AI_UPSTREAM_HOST}"
export VAULT_REMOTE_SERVER_NAME="${VAULT_REMOTE_SERVER_NAME}"
export OPENCLAW_REMOTE_SERVER_NAME="${OPENCLAW_REMOTE_SERVER_NAME}"
export VAULT_REMOTE_UPSTREAM_HOSTPORT="${VAULT_REMOTE_UPSTREAM_HOSTPORT}"
export OPENCLAW_REMOTE_UPSTREAM_HOSTPORT="${OPENCLAW_REMOTE_UPSTREAM_HOSTPORT}"
exec "${CADDY_BIN}" run --config "${ACTIVE_CADDYFILE}" --adapter caddyfile
EOF
  chmod +x "$RUN_SCRIPT"
}

write_plist() {
  mkdir -p "$(dirname "$PLIST_FILE")" "$STATE_DIR"
  cat >"$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUN_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${STATE_DIR}</string>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
}

service_loaded() {
  launchctl print "${LAUNCHD_DOMAIN}/${PLIST_LABEL}" >/dev/null 2>&1
}

prepare() {
  load_env
  select_caddyfile
  require_cmd dig
  ensure_ports
  ensure_binary
  render_runtime_exports
  write_launch_script
}

build() {
  ensure_binary
  log "binary ready: ${CADDY_BIN}"
}

validate() {
  prepare
  if [[ "${CADDY_TLS_MODE}" == "dns" ]]; then
    export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-0123456789abcdef0123456789abcdef01234567}"
  fi
  "${CADDY_BIN}" validate --config "$ACTIVE_CADDYFILE" --adapter caddyfile
  log "validation passed"
}

up() {
  prepare
  [[ -n "${CADDY_ACME_EMAIL:-}" ]] || die "missing CADDY_ACME_EMAIL in ${ENV_FILE}"
  if [[ "${CADDY_TLS_MODE}" == "dns" ]]; then
    [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || die "missing CLOUDFLARE_API_TOKEN in ${ENV_FILE}"
  fi

  write_plist
  : >"$LOG_FILE"

  if service_loaded; then
    launchctl kickstart -k "${LAUNCHD_DOMAIN}/${PLIST_LABEL}" >/dev/null
  else
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST_FILE"
  fi

  sleep 2
  log "caddy edge started on :${LOCAL_EDGE_HTTP_PORT}/:${LOCAL_EDGE_HTTPS_PORT} (${CADDY_TLS_MODE})"
}

down() {
  launchctl bootout "${LAUNCHD_DOMAIN}/${PLIST_LABEL}" >/dev/null 2>&1 || true
  log "stopped"
}

status() {
  if ! service_loaded; then
    log "launch agent ${PLIST_LABEL} is not loaded"
    return 1
  fi
  launchctl print "${LAUNCHD_DOMAIN}/${PLIST_LABEL}" | rg 'state =|pid =|path =|last exit code|stdout path|stderr path'
}

logs() {
  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE"
  tail -n 100 -f "$LOG_FILE"
}

hosts_print() {
  cat <<'EOF'
127.0.0.1 ai.svc.plus vault.svc.plus openclaw.svc.plus
EOF
}

dns_status() {
  load_env
  for host in ai.svc.plus vault.svc.plus openclaw.svc.plus; do
    printf '== %s ==\n' "$host"
    printf 'public (%s): ' "$DNS_RESOLVER"
    dig @"${DNS_RESOLVER}" +short "$host" A | paste -sd ',' -
    printf 'macOS local: '
    dscacheutil -q host -a name "$host" 2>/dev/null | awk '/ip_address:/ {print $2}' | paste -sd ',' -
  done
}

verify() {
  load_env
  select_caddyfile
  ensure_binary
  require_cmd curl
  local -a tls_args=()
  local https_port
  local token
  https_port="${LOCAL_EDGE_HTTPS_PORT}"
  token="$(grep '^AI_GATEWAY_ACCESS_TOKEN=' "${ROOT_DIR}/deploy/apisix/macos/.env.local" | cut -d= -f2-)"

  if [[ "${CADDY_TLS_MODE}" == "internal" ]]; then
    local ca_cert="${HOME}/Library/Application Support/Caddy/pki/authorities/local/root.crt"
    [[ -f "$ca_cert" ]] || die "missing local Caddy root CA: $ca_cert"
    tls_args=(--cacert "$ca_cert")
  fi

  curl --fail --silent --show-error \
    "${tls_args[@]}" \
    --resolve "ai.svc.plus:${https_port}:127.0.0.1" \
    -H "Authorization: Bearer ${token}" \
    "https://ai.svc.plus:${https_port}/v1/models" >/dev/null

  curl --fail --silent --show-error \
    "${tls_args[@]}" \
    --resolve "vault.svc.plus:${https_port}:127.0.0.1" \
    "https://vault.svc.plus:${https_port}/v1/sys/health" >/dev/null

  curl --fail --silent --show-error \
    "${tls_args[@]}" \
    --resolve "openclaw.svc.plus:${https_port}:127.0.0.1" \
    "https://openclaw.svc.plus:${https_port}/health" >/dev/null

  log "verification passed for ai/vault/openclaw over TLS"
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || {
  usage
  exit 1
}

case "$ACTION" in
  build)
    build
    ;;
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
  verify)
    verify
    ;;
  hosts-print)
    hosts_print
    ;;
  dns-status)
    dns_status
    ;;
  *)
    usage
    exit 1
    ;;
esac
