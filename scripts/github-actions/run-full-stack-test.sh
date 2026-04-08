#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-}"
shift || true

case "$MODE" in
  pr)
    TARGET="${1:?target is required}"
    ENV_NAME="${2:-dev}"
    exec go run ./cmd/full-stack-test run --mcp="$TARGET" --suite=smoke --env="$ENV_NAME" --intent=smoke --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/${TARGET}.json"
    ;;
  release)
    TARGET="${1:?target is required}"
    ENV_NAME="${2:-pre}"
    exec go run ./cmd/full-stack-test run --mcp="$TARGET" --suite=e2e --env="$ENV_NAME" --intent=full --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/${TARGET}.json"
    ;;
  pr-full)
    ENV_NAME="${1:-dev}"
    exec go run ./cmd/full-stack-test run --event=pr --suite=smoke --env="$ENV_NAME" --intent=smoke --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/pr-full.json"
    ;;
  *)
    echo "usage: $0 <pr|release|pr-full> [target] [env]" >&2
    exit 2
    ;;
esac
