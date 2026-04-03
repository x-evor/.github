#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <node-name> <dry-run|apply>" >&2
  exit 1
fi

node_name="$1"
mode="$2"
case "${mode}" in
  dry-run|apply)
    ;;
  *)
    echo "unknown mode: ${mode}" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_path="$(cd "${script_dir}/../.." && pwd)"
playbooks_repo_path="${PLAYBOOKS_REPO_PATH:-/Users/shenlan/workspaces/cloud-neutral-toolkit/playbooks}"
env_file="${control_repo_path}/.env"
inventory_file="${playbooks_repo_path}/inventory.ini"
ansible_cfg="${playbooks_repo_path}/ansible.cfg"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
filtered_env_file="${tmpdir}/env.filtered"

if [[ ! -f "${env_file}" ]]; then
  echo "missing ${env_file}; copy .env.example to .env and fill the required values first" >&2
  exit 1
fi

if [[ ! -f "${inventory_file}" ]]; then
  echo "missing ${inventory_file}" >&2
  exit 1
fi

if ! awk -v node_name="${node_name}" '
  $1 == node_name { found = 1 }
  END { exit found ? 0 : 1 }
' "${inventory_file}"; then
  echo "node ${node_name} not found in ${inventory_file}" >&2
  exit 1
fi

set -a
grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=.*$' "${env_file}" > "${filtered_env_file}"
# shellcheck disable=SC1090
source "${filtered_env_file}"
set +a

: "${GITOPS_REPO:?GITOPS_REPO is required}"
: "${VAULT_URL:?VAULT_URL is required}"
: "${VAULT_TOKEN:?VAULT_TOKEN is required}"
: "${VAULT_ROOT_TOKEN:?VAULT_ROOT_TOKEN is required}"

: "${CLOUDFLARE_API_TOKEN:=${CLOUDFLARE_DNS_API_TOKEN:-}}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN or CLOUDFLARE_DNS_API_TOKEN is required}"
vault_init_phase="${K3S_PLATFORM_VAULT_INIT_PHASE:-post_flux}"

cd "${playbooks_repo_path}"

export ANSIBLE_CONFIG="${ansible_cfg}"
export ANSIBLE_SSH_ARGS="${ANSIBLE_SSH_ARGS:--o ControlMaster=no -o ControlPersist=no -o ConnectionAttempts=5 -o ServerAliveInterval=30 -o ServerAliveCountMax=6}"
export K3S_PLATFORM_VAULT_INIT_PHASE="${vault_init_phase}"

ansible_args=(
  ansible-playbook
  -i "${inventory_file}"
  -D
  -l "${node_name}"
)

if [[ "${mode}" == "dry-run" ]]; then
  ansible_args+=(-C)
fi

ansible_args+=(
  "${playbooks_repo_path}/k3s_platform_bootstrap_with_gitops.yml"
)

"${ansible_args[@]}"
