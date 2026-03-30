#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <dry-run|deploy> <target-host-ip>" >&2
  exit 1
fi

mode="$1"
target_host_ip="$2"

case "${mode}" in
  dry-run|deploy)
    ;;
  *)
    echo "unknown mode: ${mode}" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_path="$(cd "${script_dir}/../.." && pwd)"

if [[ -f "${control_repo_path}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${control_repo_path}/.env"
  set +a
fi

: "${INTERNAL_SERVICE_TOKEN:?INTERNAL_SERVICE_TOKEN is required}"
: "${CLOUDFLARE_DNS_API_TOKEN:=${CLOUDFLARE_API_TOKEN:-}}"
: "${CLOUDFLARE_DNS_API_TOKEN:?CLOUDFLARE_DNS_API_TOKEN or CLOUDFLARE_API_TOKEN is required}"

inventory_file="${control_repo_path}/ansible/inventory.ini"
playbook_path="${control_repo_path}/ansible/playbooks/deploy_jp_xhttp_contabo.yml"

args=(
  ansible-playbook
  -i "${inventory_file}"
  -D
  "${playbook_path}"
  -e "target_host_ip=${target_host_ip}"
)

if [[ "${mode}" == "dry-run" ]]; then
  args+=(-C)
fi

ANSIBLE_CONFIG="${control_repo_path}/ansible/ansible.cfg" "${args[@]}"
