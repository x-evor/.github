#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${RUNNER_TEMP:-/tmp}"
LOG_FILE="${LOG_DIR}/full-stack-gateway.log"
PID_FILE="${LOG_DIR}/full-stack-gateway.pid"
ADDR="${MCP_GATEWAY_ADDR:-:8080}"

cd "$ROOT_DIR"
MCP_GATEWAY_ADDR="$ADDR" go run ./cmd/xcloud-server >"$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" >"$PID_FILE"

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:8080/healthz" >/dev/null 2>&1; then
    echo "gateway_ready=true"
    exit 0
  fi
  sleep 1
done

echo "gateway failed to start" >&2
cat "$LOG_FILE" >&2 || true
exit 1
