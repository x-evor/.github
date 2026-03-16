#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <inventory-template-path> <server-alias>" >&2
  exit 1
fi

inventory_template_path="$1"
server_alias="$2"

: "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY:?SINGLE_NODE_VPS_SSH_PRIVATE_KEY is required}"
: "${SINGLE_NODE_VPS_SSH_HOST:?SINGLE_NODE_VPS_SSH_HOST is required}"
: "${SINGLE_NODE_VPS_SSH_USER:?SINGLE_NODE_VPS_SSH_USER is required}"
: "${SINGLE_NODE_VPS_SSH_PORT:?SINGLE_NODE_VPS_SSH_PORT is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ssh_dir="${HOME}/.ssh"
private_key_file="${ssh_dir}/id_rsa"
inventory_file="$(mktemp)"

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

python3 "${script_dir}/private-key-payload.py" normalize > "${private_key_file}"
chmod 600 "${private_key_file}"

if ! ssh-keygen -y -f "${private_key_file}" >/dev/null 2>&1; then
  echo "Invalid SINGLE_NODE_VPS_SSH_PRIVATE_KEY payload: $(python3 "${script_dir}/private-key-payload.py" hint)" >&2
  exit 1
fi

python3 "${script_dir}/render-ansible-inventory.py" \
  "${inventory_template_path}" \
  "${inventory_file}" \
  "${server_alias}" \
  "${SINGLE_NODE_VPS_SSH_HOST}" \
  "${SINGLE_NODE_VPS_SSH_USER}" \
  "${SINGLE_NODE_VPS_SSH_PORT}" \
  "${private_key_file}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "inventory_file=${inventory_file}" >> "${GITHUB_OUTPUT}"
else
  echo "inventory_file=${inventory_file}"
fi
