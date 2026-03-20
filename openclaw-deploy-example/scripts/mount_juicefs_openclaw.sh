#!/usr/bin/env bash
set -euo pipefail

ACTION="status"
MOUNT_POINT="${JUICEFS_MOUNT_POINT:-/opt/data}"
META_URL="${JUICEFS_META_URL:-}"
BUCKET="${GCS_BUCKET_NAME:-openclawbot-data}"
FS_NAME="${JUICEFS_NAME:-openclawfs}"
CACHE_DIR="${JUICEFS_CACHE_DIR:-$HOME/.openclaw/cache/juicefs}"
CACHE_SIZE="${JUICEFS_CACHE_SIZE:-1024}"
WRITEBACK=1
FORCE=0

usage() {
  cat <<'EOF'
Mount an OpenClaw shared filesystem with JuiceFS backed by PostgreSQL metadata and GCS object storage.

Usage:
  scripts/mount_juicefs_openclaw.sh [format|up|down|restart|ensure|status] [options]

Options:
  --mount-point <path>       Local mount point (default: /opt/data)
  --meta-url <url>           JuiceFS metadata URL, usually PostgreSQL
  --bucket <name>            GCS bucket name used during format (default: openclawbot-data)
  --fs-name <name>           JuiceFS filesystem name for first format (default: openclawfs)
  --cache-dir <path>         JuiceFS local cache dir
  --cache-size <MiB>         JuiceFS local cache size in MiB (default: 1024)
  --no-writeback             Disable JuiceFS writeback cache
  --force                    Force unmount when supported
  -h, --help                 Show help

Environment:
  JUICEFS_META_URL
  META_PASSWORD
  GOOGLE_APPLICATION_CREDENTIALS
  GCS_BUCKET_NAME
  JUICEFS_NAME
  JUICEFS_CACHE_DIR
  JUICEFS_CACHE_SIZE
EOF
}

log() {
  printf '[openclaw-juicefs] %s\n' "$*"
}

fail() {
  printf '[openclaw-juicefs] ERROR: %s\n' "$*" >&2
  exit 1
}

require_juicefs() {
  command -v juicefs >/dev/null 2>&1 || fail "Missing command: juicefs"
}

require_meta_url() {
  [[ -n "$META_URL" ]] || fail "Missing JuiceFS metadata URL. Set JUICEFS_META_URL or pass --meta-url."
}

ensure_dirs() {
  mkdir -p "$MOUNT_POINT"
  mkdir -p "$CACHE_DIR"
}

is_mounted() {
  mount | grep -F " on ${MOUNT_POINT} " >/dev/null 2>&1
}

is_readable() {
  ls "$MOUNT_POINT" >/dev/null 2>&1
}

format_fs() {
  require_meta_url
  log "Formatting JuiceFS filesystem '${FS_NAME}' on bucket '${BUCKET}'"
  juicefs format --storage gs --bucket "$BUCKET" "$META_URL" "$FS_NAME"
}

mount_up() {
  require_meta_url
  ensure_dirs

  if is_mounted && is_readable; then
    log "Mount already healthy at ${MOUNT_POINT}"
    return 0
  fi

  if is_mounted; then
    log "Mount exists but is not readable, remounting"
    mount_down
  fi

  local cmd=(juicefs mount -d --cache-dir "$CACHE_DIR" --cache-size "$CACHE_SIZE")
  if ((WRITEBACK)); then
    cmd+=(--writeback)
  fi
  cmd+=("$META_URL" "$MOUNT_POINT")

  log "Mounting JuiceFS at ${MOUNT_POINT}"
  "${cmd[@]}"
}

mount_down() {
  if ! is_mounted; then
    log "Mount is already absent: ${MOUNT_POINT}"
    return 0
  fi

  local cmd=(juicefs umount)
  if ((FORCE)); then
    cmd+=(--force)
  fi
  cmd+=("$MOUNT_POINT")

  log "Unmounting ${MOUNT_POINT}"
  "${cmd[@]}"
}

status_fs() {
  log "action=status mount=${MOUNT_POINT} bucket=${BUCKET} fs=${FS_NAME} cache=${CACHE_DIR}"
  if [[ -n "$META_URL" ]]; then
    juicefs status "$META_URL" || true
  fi
  mount | grep -F " on ${MOUNT_POINT} " || true
  pgrep -af "juicefs mount.*${MOUNT_POINT}" || true
}

ensure_fs() {
  if is_mounted && is_readable; then
    log "Mount is healthy"
    return 0
  fi
  mount_up
}

if [[ $# -gt 0 && "$1" != --* && "$1" != "-h" ]]; then
  ACTION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-point)
      [[ $# -ge 2 ]] || fail "Missing value for --mount-point"
      MOUNT_POINT="$2"
      shift 2
      ;;
    --meta-url)
      [[ $# -ge 2 ]] || fail "Missing value for --meta-url"
      META_URL="$2"
      shift 2
      ;;
    --bucket)
      [[ $# -ge 2 ]] || fail "Missing value for --bucket"
      BUCKET="$2"
      shift 2
      ;;
    --fs-name)
      [[ $# -ge 2 ]] || fail "Missing value for --fs-name"
      FS_NAME="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || fail "Missing value for --cache-dir"
      CACHE_DIR="$2"
      shift 2
      ;;
    --cache-size)
      [[ $# -ge 2 ]] || fail "Missing value for --cache-size"
      CACHE_SIZE="$2"
      shift 2
      ;;
    --no-writeback)
      WRITEBACK=0
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_juicefs

case "$ACTION" in
  format)
    format_fs
    ;;
  up)
    mount_up
    ;;
  down)
    mount_down
    ;;
  restart)
    mount_down
    mount_up
    ;;
  ensure)
    ensure_fs
    ;;
  status)
    status_fs
    ;;
  *)
    fail "Unknown action: ${ACTION}"
    ;;
esac
