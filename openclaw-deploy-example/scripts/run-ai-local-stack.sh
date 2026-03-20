#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_SCRIPT="${ROOT_DIR}/deploy/vault/scripts/run-local-macos.sh"
APISIX_SCRIPT="${ROOT_DIR}/deploy/apisix/scripts/run-local-macos.sh"
OPENCLAW_SCRIPT="${ROOT_DIR}/scripts/run-openclaw-local.sh"
CADDY_SCRIPT="${ROOT_DIR}/scripts/run-local-caddy.sh"

usage() {
  cat <<'EOF'
Usage: scripts/run-ai-local-stack.sh <up|down|restart|status|up-with-edge|down-with-edge|restart-with-edge|edge-status|edge-verify>
EOF
}

run_step() {
  local script="$1"
  local action="$2"
  "$script" "$action"
}

status_local() {
  run_step "$VAULT_SCRIPT" status || true
  run_step "$APISIX_SCRIPT" status || true
  run_step "$OPENCLAW_SCRIPT" status || true
}

status_all() {
  status_local
  run_step "$CADDY_SCRIPT" status || true
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || {
  usage
  exit 1
}

case "$ACTION" in
  up)
    run_step "$VAULT_SCRIPT" up
    run_step "$OPENCLAW_SCRIPT" up
    run_step "$APISIX_SCRIPT" up
    status_local
    ;;
  down)
    run_step "$APISIX_SCRIPT" down || true
    run_step "$OPENCLAW_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" down || true
    ;;
  restart)
    run_step "$APISIX_SCRIPT" down || true
    run_step "$OPENCLAW_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" up
    run_step "$OPENCLAW_SCRIPT" up
    run_step "$APISIX_SCRIPT" up
    status_local
    ;;
  status)
    status_local
    ;;
  up-with-edge)
    run_step "$VAULT_SCRIPT" up
    run_step "$OPENCLAW_SCRIPT" up
    run_step "$APISIX_SCRIPT" up
    run_step "$CADDY_SCRIPT" up
    status_all
    ;;
  down-with-edge)
    run_step "$CADDY_SCRIPT" down || true
    run_step "$APISIX_SCRIPT" down || true
    run_step "$OPENCLAW_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" down || true
    ;;
  restart-with-edge)
    run_step "$CADDY_SCRIPT" down || true
    run_step "$APISIX_SCRIPT" down || true
    run_step "$OPENCLAW_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" down || true
    run_step "$VAULT_SCRIPT" up
    run_step "$OPENCLAW_SCRIPT" up
    run_step "$APISIX_SCRIPT" up
    run_step "$CADDY_SCRIPT" up
    status_all
    ;;
  edge-status)
    run_step "$CADDY_SCRIPT" status
    ;;
  edge-verify)
    run_step "$CADDY_SCRIPT" verify
    ;;
  *)
    usage
    exit 1
    ;;
esac
