#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_local_image_tar.sh \
    --context <dir> \
    --image <name> \
    --tag <tag> \
    --tar <output.tar> \
    [--dockerfile <path>] \
    [--platform <platform>]

Example:
  build_local_image_tar.sh \
    --context /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus \
    --image local/accounts \
    --tag d5009762 \
    --tar /tmp/accounts-d5009762.tar \
    --platform linux/amd64
EOF
}

CONTEXT=""
IMAGE=""
TAG=""
OUTPUT_TAR=""
DOCKERFILE=""
PLATFORM="linux/amd64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --image)
      IMAGE="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --tar)
      OUTPUT_TAR="$2"
      shift 2
      ;;
    --dockerfile)
      DOCKERFILE="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
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

if [[ -z "$CONTEXT" || -z "$IMAGE" || -z "$TAG" || -z "$OUTPUT_TAR" ]]; then
  usage >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found. Install OrbStack or another Docker runtime first." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not reachable. Start OrbStack first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_TAR")"

BUILD_ARGS=(docker build --platform "$PLATFORM" -t "${IMAGE}:${TAG}")
if [[ -n "$DOCKERFILE" ]]; then
  BUILD_ARGS+=(-f "$DOCKERFILE")
fi
BUILD_ARGS+=("$CONTEXT")

echo "==> Building ${IMAGE}:${TAG}"
"${BUILD_ARGS[@]}"

echo "==> Saving ${IMAGE}:${TAG} to ${OUTPUT_TAR}"
docker save -o "$OUTPUT_TAR" "${IMAGE}:${TAG}"

echo "==> Done"
docker image inspect "${IMAGE}:${TAG}" --format 'image={{.RepoTags}} os={{.Os}} arch={{.Architecture}}'
ls -lh "$OUTPUT_TAR"
