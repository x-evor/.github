#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_BASE_DIR="${ROOT_DIR}/example/vps"

REMOTE_HOST="${SYNC_REMOTE_HOST:-root@openclaw.svc.plus}"
REMOTE_DIR="${SYNC_REMOTE_DIR:-/opt/svc-ai-gateway}"
WITH_ENV=0
WITH_EDGE=0

SHARED_FILES=(
  "conf/apisix.yaml"
  "conf/config.yaml"
  "docker-compose.yml"
  "docs/api.md"
  "docs/models.md"
  "docs/providers.md"
  "scripts/reload.sh"
  "scripts/validate.sh"
)

EDGE_FILES=(
  "Caddyfile"
)

ENV_FILES=(
  ".env"
)

usage() {
  cat <<'EOF'
Usage: scripts/sync-config.sh <diff|pull|push> [--with-env] [--with-edge] [--remote-host host] [--remote-dir dir]
EOF
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || {
  usage
  exit 1
}
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-env)
      WITH_ENV=1
      ;;
    --with-edge)
      WITH_EDGE=1
      ;;
    --remote-host)
      REMOTE_HOST="$2"
      shift
      ;;
    --remote-dir)
      REMOTE_DIR="$2"
      shift
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

command -v rsync >/dev/null || {
  printf 'rsync is required\n' >&2
  exit 1
}

mkdir -p "$LOCAL_BASE_DIR"

FILES=("${SHARED_FILES[@]}")
if [[ "$WITH_EDGE" -eq 1 ]]; then
  FILES+=("${EDGE_FILES[@]}")
fi
if [[ "$WITH_ENV" -eq 1 ]]; then
  FILES+=("${ENV_FILES[@]}")
fi

MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT
printf '%s\n' "${FILES[@]}" >"$MANIFEST"

case "$ACTION" in
  diff)
    rsync -ani --omit-dir-times --files-from="$MANIFEST" "${REMOTE_HOST}:${REMOTE_DIR}/" "${LOCAL_BASE_DIR}/"
    ;;
  pull)
    rsync -az --omit-dir-times --files-from="$MANIFEST" "${REMOTE_HOST}:${REMOTE_DIR}/" "${LOCAL_BASE_DIR}/"
    printf '[svc-ai-gateway-sync] pulled shared config from %s:%s\n' "$REMOTE_HOST" "$REMOTE_DIR"
    ;;
  push)
    rsync -az --omit-dir-times --files-from="$MANIFEST" "${LOCAL_BASE_DIR}/" "${REMOTE_HOST}:${REMOTE_DIR}/"
    printf '[svc-ai-gateway-sync] pushed shared config to %s:%s\n' "$REMOTE_HOST" "$REMOTE_DIR"
    ;;
  *)
    usage
    exit 1
    ;;
esac
