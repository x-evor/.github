#!/bin/bash
set -euo pipefail

ROOT_DIR="/private/tmp/codex-task5-control"

cd "${ROOT_DIR}"

python3 ./scripts/github-actions/stable-release-gate.py \
  --mode local \
  --service docs \
  --track prod \
  --service-ref main

server_state="$(mktemp)"
trap '[[ -n "${server_pid:-}" ]] && kill "${server_pid}" >/dev/null 2>&1 || true; rm -f "${server_state}"' EXIT

python3 - "${server_state}" <<'PY' &
import http.server
import socketserver
import sys
from pathlib import Path


state_path = Path(sys.argv[1])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        return


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as server:
    state_path.write_text(str(server.server_address[1]), encoding="utf-8")
    server.serve_forever()
PY

server_pid=$!
while [[ ! -s "${server_state}" ]]; do
  sleep 0.1
done

server_port="$(cat "${server_state}")"

python3 ./scripts/github-actions/stable-release-gate.py \
  --mode stable \
  --service docs \
  --track prod \
  --service-ref main \
  --stable-url "http://127.0.0.1:${server_port}/healthz" \
  --timeout-seconds 5

echo "stable release gate test passed"
