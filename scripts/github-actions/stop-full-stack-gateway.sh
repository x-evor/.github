#!/usr/bin/env bash
set -euo pipefail

PID_FILE="${RUNNER_TEMP:-/tmp}/full-stack-gateway.pid"
if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE")"
  if [[ -n "$PID" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
  fi
fi
