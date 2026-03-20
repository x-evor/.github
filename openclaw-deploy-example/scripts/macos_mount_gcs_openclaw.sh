#!/usr/bin/env bash
set -euo pipefail

ACTION="up"
BUCKET_NAME="${GCS_BUCKET_NAME:-openclawbot-data}"
REMOTE_NAME="gcs"
REMOTE_PATH=""
MOUNT_POINT="/opt/data"
ENV_FILE=""
FORCE_REMOUNT=0
INSTALL_LAUNCHD=0
LAUNCHCTL_MODE="status"
LAUNCHD_LABEL="ai.openclaw.gcs-rclone-mount"
VFS_CACHE_MODE="full"
CACHE_DIR="${HOME}/.openclaw/cache/rclone-vfs"
RCLONE_BIN=""
RCLONE_EXTRA_ARGS=()
PID_FILE="${HOME}/.openclaw/run/gcs-rclone-mount.pid"
LOG_FILE="${HOME}/Library/Logs/openclaw/gcs-rclone-mount.log"

usage() {
  cat <<'EOF'
Mount a GCS bucket on macOS for shared memory sync, recovery, or optional OpenClaw state storage (rclone-only).

Usage:
  scripts/macos_mount_gcs_openclaw.sh [up|down|restart|ensure|status|launchctl] [options]

Actions:
  up                    Mount and run in background (default action)
  down                  Stop mount process/service and unmount
  restart               Stop/unmount first, then mount again
  ensure                Verify mount health; auto-restart if stale/unresponsive
  status                Show mount + process + launchd status
  launchctl             Manage launchd service explicitly

Options:
  --bucket <name>            GCS bucket name (default: $GCS_BUCKET_NAME or openclawbot-data)
  --remote <name>            rclone remote name (default: gcs)
  --remote-path <path>       Full rclone path (e.g. gcs:openclawbot-data/prefix)
  --mount-point <path>       Local mount point (default: /opt/data)
  --cache-dir <path>         rclone cache dir (default: ~/.openclaw/cache/rclone-vfs)
  --vfs-cache-mode <mode>    rclone vfs cache mode (default: full)
  --env-file <path>          Optionally update OPENCLAW_STATE_DIR in this env file
  --force-remount            Unmount first if already mounted
  --install-launchd          Install/start a launchd service (KeepAlive + RunAtLoad)
  --launchctl-mode <mode>    launchctl mode: install|start|stop|restart|uninstall|status|print
  --launchd-label <label>    launchd label (default: ai.openclaw.gcs-rclone-mount)
  --log-file <path>          rclone log file path
  --pid-file <path>          PID file for non-launchd background process
  --rclone-arg <arg>         Extra rclone arg (repeatable)
  -h, --help                 Show this help

Environment:
  GCS_BUCKET_NAME            Default bucket name when --bucket is omitted
EOF
}

log() {
  printf '[openclaw-gcs] %s\n' "$*"
}

fail() {
  printf '[openclaw-gcs] ERROR: %s\n' "$*" >&2
  exit 1
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || fail "This script only supports macOS"
}

require_rclone() {
  if ! command -v rclone >/dev/null 2>&1; then
    cat >&2 <<'EOF'
[openclaw-gcs] ERROR: Missing command: rclone
Install rclone first:
  brew install rclone
EOF
    exit 1
  fi
  RCLONE_BIN="$(command -v rclone)"
}

resolve_remote_source() {
  if [ -n "$REMOTE_PATH" ]; then
    printf '%s' "$REMOTE_PATH"
    return 0
  fi
  printf '%s:%s' "$REMOTE_NAME" "$BUCKET_NAME"
}

is_mounted() {
  mount | awk -v mount_point="$MOUNT_POINT" '$0 ~ (" on " mount_point " ") {found=1} END {exit found ? 0 : 1}'
}

is_mount_readable() {
  /usr/bin/python3 -c '
import os, signal, sys
def on_alarm(_signum, _frame):
    raise TimeoutError()
signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(5)
try:
    os.listdir(sys.argv[1])
except Exception:
    sys.exit(1)
finally:
    signal.alarm(0)
' "$MOUNT_POINT" >/dev/null 2>&1
}

ensure_dir_writable() {
  local dir="$1"
  if [ -d "$dir" ]; then
    return 0
  fi
  mkdir -p "$dir"
}

ensure_mount_dir() {
  if [ -d "$MOUNT_POINT" ]; then
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "$MOUNT_POINT")"
  if [ -w "$parent_dir" ]; then
    mkdir -p "$MOUNT_POINT"
    return 0
  fi

  log "Creating $MOUNT_POINT with sudo"
  sudo mkdir -p "$MOUNT_POINT"
  sudo chown "$USER":staff "$MOUNT_POINT"
}

write_env_binding() {
  local binding_line
  binding_line="OPENCLAW_STATE_DIR=$MOUNT_POINT"

  if [ -z "$ENV_FILE" ]; then
    log "Env binding: $binding_line"
    log "Use in shell: export $binding_line"
    return 0
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v line="$binding_line" '
    BEGIN {replaced = 0}
    /^OPENCLAW_STATE_DIR=/ {
      if (replaced == 0) {
        print line
        replaced = 1
      }
      next
    }
    {print}
    END {
      if (replaced == 0) {
        print line
      }
    }
  ' "$ENV_FILE" >"$tmp_file"
  mv "$tmp_file" "$ENV_FILE"
  log "Updated $ENV_FILE with $binding_line"
}

unmount_mountpoint() {
  if ! is_mounted; then
    return 0
  fi

  log "Unmounting $MOUNT_POINT"
  if ! umount "$MOUNT_POINT" >/dev/null 2>&1; then
    diskutil unmount force "$MOUNT_POINT" >/dev/null 2>&1 || fail "Failed to unmount $MOUNT_POINT"
  fi
}

is_pid_running() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

read_pid_file() {
  if [ ! -f "$PID_FILE" ]; then
    return 1
  fi
  tr -d '[:space:]' <"$PID_FILE"
}

stop_pid_file_process() {
  local pid
  pid="$(read_pid_file || true)"
  if [ -z "$pid" ]; then
    return 0
  fi

  if is_pid_running "$pid"; then
    log "Stopping background mount process PID=$pid"
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_running "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$PID_FILE"
}

stop_mountpoint_rclone_processes() {
  pkill -f "rclone nfsmount .* ${MOUNT_POINT}" >/dev/null 2>&1 || true
}

launchd_plist_path() {
  printf '%s/Library/LaunchAgents/%s.plist' "$HOME" "$LAUNCHD_LABEL"
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

launchd_is_loaded() {
  launchctl print "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1
}

launchd_require_plist() {
  local plist
  plist="$(launchd_plist_path)"
  [ -f "$plist" ] || fail "launchd plist not found: $plist (run launchctl --launchctl-mode install or up --install-launchd)"
}

build_rclone_args() {
  local remote_source
  remote_source="$(resolve_remote_source)"

  local args=(
    "nfsmount"
    "$remote_source"
    "$MOUNT_POINT"
    "--vfs-cache-mode=${VFS_CACHE_MODE}"
    "--cache-dir=${CACHE_DIR}"
    "--log-file=${LOG_FILE}"
    "--log-format=date,time,pid"
    "--log-level=INFO"
  )

  if [ "${#RCLONE_EXTRA_ARGS[@]}" -gt 0 ]; then
    args+=("${RCLONE_EXTRA_ARGS[@]}")
  fi

  printf '%s\0' "${args[@]}"
}

wait_until_mounted() {
  local seconds="${1:-30}"
  local i
  for ((i = 0; i < seconds; i++)); do
    if is_mounted; then
      return 0
    fi
    sleep 1
  done
  return 1
}

install_launchd_service() {
  local plist
  plist="$(launchd_plist_path)"

  mkdir -p "$(dirname "$plist")"
  mkdir -p "$(dirname "$LOG_FILE")"

  local args=()
  while IFS= read -r -d '' item; do
    args+=("$item")
  done < <(build_rclone_args)

  local tmp_file
  tmp_file="$(mktemp)"
  {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$(xml_escape "$LAUNCHD_LABEL")</string>
    <key>ProgramArguments</key>
    <array>
      <string>$(xml_escape "$RCLONE_BIN")</string>
EOF
    local arg
    for arg in "${args[@]}"; do
      printf '      <string>%s</string>\n' "$(xml_escape "$arg")"
    done
    cat <<EOF
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$(xml_escape "$HOME")</string>
    <key>StandardOutPath</key>
    <string>$(xml_escape "$LOG_FILE")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "$LOG_FILE")</string>
  </dict>
</plist>
EOF
  } >"$tmp_file"
  mv "$tmp_file" "$plist"

  if launchd_is_loaded; then
    launchctl bootout "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi

  launchctl bootstrap "gui/$UID" "$plist" >/dev/null
  launchctl enable "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  log "launchd service installed: $plist"
}

stop_launchd_service() {
  if launchd_is_loaded; then
    log "Stopping launchd service: $LAUNCHD_LABEL"
    launchctl bootout "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi
}

start_launchd_service() {
  local plist
  plist="$(launchd_plist_path)"
  launchd_require_plist
  if ! launchd_is_loaded; then
    launchctl bootstrap "gui/$UID" "$plist" >/dev/null
  fi
  launchctl enable "gui/$UID/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$UID/$LAUNCHD_LABEL" >/dev/null
  log "launchd service started: $LAUNCHD_LABEL"
}

restart_launchd_service() {
  stop_launchd_service
  start_launchd_service
}

uninstall_launchd_service() {
  local plist
  plist="$(launchd_plist_path)"
  stop_launchd_service
  if [ -f "$plist" ]; then
    rm -f "$plist"
    log "launchd service removed: $plist"
  else
    log "launchd service plist already absent: $plist"
  fi
}

print_launchd_service() {
  launchctl print "gui/$UID/$LAUNCHD_LABEL"
}

up_action() {
  ensure_mount_dir
  ensure_dir_writable "$CACHE_DIR"
  ensure_dir_writable "$(dirname "$PID_FILE")"
  ensure_dir_writable "$(dirname "$LOG_FILE")"

  if is_mounted; then
    if [ "$INSTALL_LAUNCHD" -eq 1 ]; then
      log "$MOUNT_POINT is already mounted; switching mount supervision to launchd"
      stop_pid_file_process
      unmount_mountpoint
    elif [ "$FORCE_REMOUNT" -eq 0 ]; then
      log "$MOUNT_POINT is already mounted; skipping mount"
      write_env_binding
      return 0
    fi
    if [ "$INSTALL_LAUNCHD" -eq 0 ]; then
      stop_launchd_service
      stop_pid_file_process
      unmount_mountpoint
    fi
  fi

  if [ "$INSTALL_LAUNCHD" -eq 1 ]; then
    install_launchd_service
    if ! wait_until_mounted 40; then
      fail "launchd started but mount not ready at $MOUNT_POINT (check $LOG_FILE)"
    fi
    log "Mount is active via launchd"
    write_env_binding
    return 0
  fi

  local args=()
  while IFS= read -r -d '' item; do
    args+=("$item")
  done < <(build_rclone_args)

  # rclone stays in foreground by default, so we background it for one-command usage.
  nohup "$RCLONE_BIN" "${args[@]}" >>"$LOG_FILE" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$PID_FILE"
  log "Started rclone nfsmount in background: PID=$pid"

  if ! wait_until_mounted 40; then
    fail "Mount not ready at $MOUNT_POINT (check $LOG_FILE)"
  fi
  log "Mount successful: $(resolve_remote_source) -> $MOUNT_POINT"
  write_env_binding
}

down_action() {
  stop_launchd_service
  stop_pid_file_process
  unmount_mountpoint
  log "Unmount complete"
}

restart_action() {
  FORCE_REMOUNT=1
  down_action
  up_action
}

status_action() {
  local remote_source
  remote_source="$(resolve_remote_source)"

  log "Remote source: $remote_source"
  log "Mount point: $MOUNT_POINT"
  log "Cache dir: $CACHE_DIR"
  log "VFS cache mode: $VFS_CACHE_MODE"
  log "Log file: $LOG_FILE"

  if is_mounted; then
    log "Mounted: yes"
    if is_mount_readable; then
      log "Mount health: readable"
    else
      log "Mount health: unresponsive"
    fi
  else
    log "Mounted: no"
  fi

  local pid
  pid="$(read_pid_file || true)"
  if [ -n "$pid" ] && is_pid_running "$pid"; then
    log "Background PID file process: running (PID=$pid)"
  elif [ -n "$pid" ]; then
    log "Background PID file process: stale PID=$pid"
  else
    log "Background PID file process: none"
  fi

  if launchd_is_loaded; then
    log "launchd service: loaded ($LAUNCHD_LABEL)"
  elif [ -f "$(launchd_plist_path)" ]; then
    log "launchd service: installed but not loaded ($LAUNCHD_LABEL)"
  else
    log "launchd service: not installed"
  fi
}

ensure_action() {
  local has_launchd=0
  if launchd_is_loaded || [ -f "$(launchd_plist_path)" ]; then
    has_launchd=1
  fi

  if is_mounted && is_mount_readable; then
    log "Mount is healthy; no action needed"
    return 0
  fi

  if is_mounted; then
    log "Mount is present but unhealthy; restarting"
  else
    log "Mount is absent; starting"
  fi

  stop_launchd_service
  stop_pid_file_process
  stop_mountpoint_rclone_processes
  unmount_mountpoint

  if [ "$has_launchd" -eq 1 ]; then
    ensure_mount_dir
    ensure_dir_writable "$CACHE_DIR"
    ensure_dir_writable "$(dirname "$LOG_FILE")"
    start_launchd_service
    if ! wait_until_mounted 40; then
      fail "launchd ensure failed: mount not ready at $MOUNT_POINT (check $LOG_FILE)"
    fi
    if ! is_mount_readable; then
      fail "launchd ensure failed: mount is present but unreadable at $MOUNT_POINT (check $LOG_FILE)"
    fi
    log "Mount recovered via launchd"
    write_env_binding
    return 0
  fi

  up_action
  if ! is_mount_readable; then
    fail "mount recovered but is unreadable at $MOUNT_POINT (check $LOG_FILE)"
  fi
  log "Mount recovered"
}

launchctl_action() {
  case "$LAUNCHCTL_MODE" in
    install)
      ensure_mount_dir
      ensure_dir_writable "$CACHE_DIR"
      ensure_dir_writable "$(dirname "$LOG_FILE")"
      install_launchd_service
      ;;
    start)
      ensure_mount_dir
      ensure_dir_writable "$CACHE_DIR"
      ensure_dir_writable "$(dirname "$LOG_FILE")"
      start_launchd_service
      ;;
    stop)
      stop_launchd_service
      ;;
    restart)
      ensure_mount_dir
      ensure_dir_writable "$CACHE_DIR"
      ensure_dir_writable "$(dirname "$LOG_FILE")"
      restart_launchd_service
      ;;
    uninstall)
      uninstall_launchd_service
      ;;
    status)
      status_action
      ;;
    print)
      print_launchd_service
      ;;
    *)
      fail "Unsupported --launchctl-mode: $LAUNCHCTL_MODE"
      ;;
  esac
}

parse_args() {
  if [ "$#" -gt 0 ]; then
    case "$1" in
      up|down|restart|ensure|status|launchctl)
        ACTION="$1"
        shift
        ;;
    esac
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bucket)
        [ "$#" -ge 2 ] || fail "Missing value for --bucket"
        BUCKET_NAME="$2"
        shift 2
        ;;
      --remote)
        [ "$#" -ge 2 ] || fail "Missing value for --remote"
        REMOTE_NAME="$2"
        shift 2
        ;;
      --remote-path)
        [ "$#" -ge 2 ] || fail "Missing value for --remote-path"
        REMOTE_PATH="$2"
        shift 2
        ;;
      --mount-point)
        [ "$#" -ge 2 ] || fail "Missing value for --mount-point"
        MOUNT_POINT="$2"
        shift 2
        ;;
      --cache-dir)
        [ "$#" -ge 2 ] || fail "Missing value for --cache-dir"
        CACHE_DIR="$2"
        shift 2
        ;;
      --vfs-cache-mode)
        [ "$#" -ge 2 ] || fail "Missing value for --vfs-cache-mode"
        VFS_CACHE_MODE="$2"
        shift 2
        ;;
      --env-file)
        [ "$#" -ge 2 ] || fail "Missing value for --env-file"
        ENV_FILE="$2"
        shift 2
        ;;
      --force-remount)
        FORCE_REMOUNT=1
        shift
        ;;
      --install-launchd)
        INSTALL_LAUNCHD=1
        shift
        ;;
      --launchctl-mode)
        [ "$#" -ge 2 ] || fail "Missing value for --launchctl-mode"
        LAUNCHCTL_MODE="$2"
        shift 2
        ;;
      --launchd-label)
        [ "$#" -ge 2 ] || fail "Missing value for --launchd-label"
        LAUNCHD_LABEL="$2"
        shift 2
        ;;
      --log-file)
        [ "$#" -ge 2 ] || fail "Missing value for --log-file"
        LOG_FILE="$2"
        shift 2
        ;;
      --pid-file)
        [ "$#" -ge 2 ] || fail "Missing value for --pid-file"
        PID_FILE="$2"
        shift 2
        ;;
      --rclone-arg)
        [ "$#" -ge 2 ] || fail "Missing value for --rclone-arg"
        RCLONE_EXTRA_ARGS+=("$2")
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  require_macos
  require_rclone

  case "$ACTION" in
    up)
      up_action
      ;;
    down)
      down_action
      ;;
    restart)
      restart_action
      ;;
    ensure)
      ensure_action
      ;;
    status)
      status_action
      ;;
    launchctl)
      launchctl_action
      ;;
    *)
      fail "Unsupported action: $ACTION"
      ;;
  esac
}

main "$@"
