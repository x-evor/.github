#!/usr/bin/env bash
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$PROJECT_DIR/deploy/docker-compose-lite"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yaml"

echo "== docker compose ps =="
docker compose -f "$COMPOSE_FILE" -p cn-toolkit-lite ps

echo
echo "== container status =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep 'cn-toolkit-' || true

echo
echo "== APISIX admin =="
curl -fsS --max-time 5 http://127.0.0.1:9180/apisix/admin/routes || echo "APISIX not reachable"

echo
echo "== Stunnel port =="
if command -v nc &> /dev/null; then
    nc -z 127.0.0.1 15432 && echo "stunnel-client port 15432 OK" || echo "stunnel-client port 15432 FAILED"
elif command -v timeout &> /dev/null; then
    timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/15432' && echo "stunnel-client port 15432 OK" || echo "stunnel-client port 15432 FAILED"
else
    echo "Neither nc nor timeout available for port check"
fi
