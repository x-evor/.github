#!/bin/bash
set -euo pipefail

# Backward-compatible wrapper:
# secure deploy logic has been merged into deploy.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy.sh" "$@"
