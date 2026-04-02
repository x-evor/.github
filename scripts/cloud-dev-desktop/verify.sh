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
state_dir="${repo_root}/.ansible/cloud-dev-desktop"
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
  --state-file "${state_file}"

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY="${OBJC_DISABLE_INITIALIZE_FORK_SAFETY:-YES}"
export no_proxy="${no_proxy:-*}"
export NO_PROXY="${NO_PROXY:-*}"

args=(ansible-playbook -i "${inventory_file}" -D "${repo_root}/ansible/playbooks/verify_cloud_dev_desktop.yml" -e "@${runtime_vars}")
if [[ "${mode}" == "dry-run" ]]; then
  args=(ansible-playbook -i "${inventory_file}" -D -C "${repo_root}/ansible/playbooks/verify_cloud_dev_desktop.yml" -e "@${runtime_vars}")
fi
ANSIBLE_CONFIG="${repo_root}/ansible/ansible.cfg" "${args[@]}"
