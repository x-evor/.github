#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ship_image_tar.sh \
    --host <ssh-host> \
    --tar <local.tar> \
    --remote-dir <dir> \
    [--keep-remote-tar]

Example:
  ship_image_tar.sh \
    --host root@us-xhttp.svc.plus \
    --tar /tmp/accounts-d5009762.tar \
    --remote-dir /opt/cloud-neutral/accounts/accounts-us-xhttp-d5009762
EOF
}

HOST=""
LOCAL_TAR=""
REMOTE_DIR=""
KEEP_REMOTE_TAR=0
SSH_OPTS=(-o ControlMaster=no -o ControlPersist=no)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --tar)
      LOCAL_TAR="$2"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="$2"
      shift 2
      ;;
    --keep-remote-tar)
      KEEP_REMOTE_TAR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" || -z "$LOCAL_TAR" || -z "$REMOTE_DIR" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$LOCAL_TAR" ]]; then
  echo "Local tar not found: $LOCAL_TAR" >&2
  exit 1
fi

REMOTE_TAR="${REMOTE_DIR}/image.tar"

echo "==> Ensuring remote directory ${REMOTE_DIR}"
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$REMOTE_DIR'"

echo "==> Transferring ${LOCAL_TAR}"
rsync -av --partial --progress -e "ssh ${SSH_OPTS[*]}" "$LOCAL_TAR" "${HOST}:${REMOTE_TAR}"

echo "==> Loading image on ${HOST}"
ssh "${SSH_OPTS[@]}" "$HOST" "docker load -i '$REMOTE_TAR'"

if [[ "$KEEP_REMOTE_TAR" -ne 1 ]]; then
  echo "==> Removing remote tar"
  ssh "${SSH_OPTS[@]}" "$HOST" "rm -f '$REMOTE_TAR'"
fi

echo "==> Done"
