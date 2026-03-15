#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <server-alias>" >&2
  exit 1
fi

server_alias="$1"

: "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY:?SINGLE_NODE_VPS_SSH_PRIVATE_KEY is required}"
: "${SINGLE_NODE_VPS_SSH_HOST:?SINGLE_NODE_VPS_SSH_HOST is required}"
: "${SINGLE_NODE_VPS_SSH_USER:?SINGLE_NODE_VPS_SSH_USER is required}"
: "${SINGLE_NODE_VPS_SSH_PORT:?SINGLE_NODE_VPS_SSH_PORT is required}"
: "${SINGLE_NODE_VPS_SSH_KNOWN_HOSTS:?SINGLE_NODE_VPS_SSH_KNOWN_HOSTS is required}"

ssh_dir="${HOME}/.ssh"
private_key_file="${ssh_dir}/id_rsa"
known_hosts_file="${ssh_dir}/known_hosts"
inventory_file="$(mktemp)"

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

printf '%s\n' "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY}" > "${private_key_file}"
chmod 600 "${private_key_file}"

printf '%s\n' "${SINGLE_NODE_VPS_SSH_KNOWN_HOSTS}" > "${known_hosts_file}"
chmod 644 "${known_hosts_file}"

cat > "${inventory_file}" <<EOF
[server]
${server_alias} ansible_host=${SINGLE_NODE_VPS_SSH_HOST} ansible_user=${SINGLE_NODE_VPS_SSH_USER}

[all:vars]
ansible_port=${SINGLE_NODE_VPS_SSH_PORT}
ansible_user=${SINGLE_NODE_VPS_SSH_USER}
ansible_ssh_private_key_file=${private_key_file}
ansible_host_key_checking=True
ansible_ssh_common_args=-o UserKnownHostsFile=${known_hosts_file}
EOF

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "inventory_file=${inventory_file}"
    echo "private_key_file=${private_key_file}"
    echo "known_hosts_file=${known_hosts_file}"
  } >> "${GITHUB_OUTPUT}"
else
  cat <<EOF
inventory_file=${inventory_file}
private_key_file=${private_key_file}
known_hosts_file=${known_hosts_file}
EOF
fi
