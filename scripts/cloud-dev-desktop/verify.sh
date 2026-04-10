#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --provider <azure|gcp> --request <path> [--dry-run]" >&2
  exit 1
}

provider=""
request=""
mode="apply"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) provider="$2"; shift 2 ;;
    --request) request="$2"; shift 2 ;;
    --dry-run) mode="dry-run"; shift ;;
    *) usage ;;
  esac
done

[[ -n "$provider" && -n "$request" ]] || usage

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playbooks_root="$(cd "${repo_root}/../playbooks" && pwd)"
state_dir="${repo_root}/.ansible/cloud-dev-desktop"
mkdir -p "${state_dir}"
runtime_vars="$(mktemp)"
inventory_file="$(mktemp)"
request_abs="$(cd "$(dirname "$request")" && pwd)/$(basename "$request")"
profile_name="$(python3 -c 'import sys,yaml;print((yaml.safe_load(open(sys.argv[1])) or {})["profile_name"])' "${request_abs}")"
state_file="${state_dir}/${provider}-${profile_name}.json"

python3 "${repo_root}/scripts/cloud-dev-desktop/render-runtime-vars.py" \
  --request "${request_abs}" \
  --provider-defaults "${repo_root}/ansible/vars/cloud_dev_desktop.${provider}.example.yml" \
  --provider-override "${provider}" \
  --runtime-vars-out "${runtime_vars}" \
  --inventory-out "${inventory_file}" \
  --state-file "${state_file}" \
  --allow-missing-ip
printf "[local_runner]\nlocalhost ansible_connection=local\n" > "${inventory_file}"

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY="${OBJC_DISABLE_INITIALIZE_FORK_SAFETY:-YES}"
export no_proxy="${no_proxy:-*}"
export NO_PROXY="${NO_PROXY:-*}"

args=(ansible-playbook -i "${inventory_file}" -D "${playbooks_root}/bootstrap_cloud_dev_desktop.yml" -e "@${runtime_vars}" -e "cloud_vm_state_file=${state_file}" -e "cloud_vm_state_root=${state_dir}")
if [[ "${mode}" == "dry-run" ]]; then
  args=(ansible-playbook -i "${inventory_file}" -D -C "${playbooks_root}/bootstrap_cloud_dev_desktop.yml" -e "@${runtime_vars}" -e "cloud_vm_state_file=${state_file}" -e "cloud_vm_state_root=${state_dir}")
fi
ANSIBLE_CONFIG="${playbooks_root}/ansible.cfg" "${args[@]}"
