#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <server-alias>" >&2
  exit 1
fi

server_alias="$1"

: "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY:?SINGLE_NODE_VPS_SSH_PRIVATE_KEY is required}"

ssh_host="${SINGLE_NODE_VPS_SSH_HOST:-${server_alias}}"
ssh_user="${SINGLE_NODE_VPS_SSH_USER:-root}"
ssh_port="${SINGLE_NODE_VPS_SSH_PORT:-22}"
ssh_known_hosts="${SINGLE_NODE_VPS_SSH_KNOWN_HOSTS:-}"

ssh_dir="${HOME}/.ssh"
private_key_file="${ssh_dir}/id_deploy"
known_hosts_file="${ssh_dir}/known_hosts"
inventory_file="$(mktemp)"

umask 077
mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

printf '%s' "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY}" | tr -d '\r' > "${private_key_file}"
printf '\n' >> "${private_key_file}"
chmod 600 "${private_key_file}"

if ! ssh-keygen -y -f "${private_key_file}" >/dev/null 2>&1; then
  echo "Invalid SINGLE_NODE_VPS_SSH_PRIVATE_KEY payload" >&2
  exit 1
fi

if [[ -n "${ssh_known_hosts}" ]]; then
  printf '%s\n' "${ssh_known_hosts}" > "${known_hosts_file}"
else
  ssh-keyscan -p "${ssh_port}" -H "${ssh_host}" > "${known_hosts_file}"
fi
chmod 644 "${known_hosts_file}"

cat > "${inventory_file}" <<EOF
[server]
${server_alias} ansible_host=${ssh_host} ansible_user=${ssh_user}

[all:vars]
ansible_port=${ssh_port}
ansible_user=${ssh_user}
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
