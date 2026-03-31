#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <inventory-path> <server-alias> <inventory-template-path>" >&2
  exit 1
fi

inventory_path="$1"
server_alias="$2"
inventory_template_path="$3"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ssh_dir="${HOME}/.ssh"
private_key_file="${ssh_dir}/id_rsa"
inventory_file="${inventory_path}"
override_ssh_host="${ANSIBLE_OVERRIDE_SSH_HOST:-}"
override_ssh_user="${ANSIBLE_OVERRIDE_SSH_USER:-}"
override_ssh_port="${ANSIBLE_OVERRIDE_SSH_PORT:-}"
override_known_hosts="${ANSIBLE_OVERRIDE_SSH_KNOWN_HOSTS:-}"
private_key_payload="${SINGLE_NODE_VPS_SSH_PRIVATE_KEY:-}"
overrides_present=false

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

if [[ -n "${private_key_payload}" ]]; then
  python3 "${script_dir}/private-key-payload.py" normalize > "${private_key_file}"
  chmod 600 "${private_key_file}"

  if ! ssh-keygen -y -f "${private_key_file}" >/dev/null 2>&1; then
    echo "Invalid SINGLE_NODE_VPS_SSH_PRIVATE_KEY payload: $(python3 "${script_dir}/private-key-payload.py" hint)" >&2
    exit 1
  fi
fi

if [[ -n "${override_known_hosts}" ]]; then
  printf '%s\n' "${override_known_hosts}" > "${ssh_dir}/known_hosts"
  chmod 644 "${ssh_dir}/known_hosts"
fi

if [[ -n "${override_ssh_host}" || -n "${override_ssh_user}" || -n "${override_ssh_port}" ]]; then
  overrides_present=true
fi

if [[ "${overrides_present}" == "true" ]]; then
  : "${private_key_payload:?SINGLE_NODE_VPS_SSH_PRIVATE_KEY is required when overriding Ansible transport variables}"
  inventory_json="$(ansible-inventory -i "${inventory_path}" --host "${server_alias}")"

  default_ssh_host="$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data.get("ansible_host",""))' <<<"${inventory_json}")"
  default_ssh_user="$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data.get("ansible_user",""))' <<<"${inventory_json}")"
  default_ssh_port="$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data.get("ansible_port",""))' <<<"${inventory_json}")"

  resolved_ssh_host="${override_ssh_host:-${default_ssh_host}}"
  resolved_ssh_user="${override_ssh_user:-${default_ssh_user}}"
  resolved_ssh_port="${override_ssh_port:-${default_ssh_port}}"

  : "${resolved_ssh_host:?Unable to resolve ansible_host for ${server_alias}}"
  : "${resolved_ssh_user:?Unable to resolve ansible_user for ${server_alias}}"
  : "${resolved_ssh_port:?Unable to resolve ansible_port for ${server_alias}}"

  inventory_file="$(mktemp)"
  python3 "${script_dir}/render-ansible-inventory.py" \
    "${inventory_template_path}" \
    "${inventory_file}" \
    "${server_alias}" \
    "${resolved_ssh_host}" \
    "${resolved_ssh_user}" \
    "${resolved_ssh_port}" \
    "${private_key_file}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "inventory_file=${inventory_file}" >> "${GITHUB_OUTPUT}"
else
  echo "inventory_file=${inventory_file}"
fi
