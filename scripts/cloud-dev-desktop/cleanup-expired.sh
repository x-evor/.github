#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --provider <azure|gcp> [--dry-run]" >&2
  exit 1
}

provider=""
mode="apply"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) provider="$2"; shift 2 ;;
    --dry-run) mode="dry-run"; shift ;;
    *) usage ;;
  esac
done

[[ -n "$provider" ]] || usage

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_vars="$(mktemp)"
inventory_file="$(mktemp)"
cat_json='{"provider":"'"${provider}"'","profile_name":"cleanup","os_family":"windows","admin_username":"cleanup","allowed_cidrs":["127.0.0.1/32"],"ttl_hours":1,"owner":"cleanup","purpose":"cleanup"}'
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); open(sys.argv[2],"w").write(json.dumps(data))' "${cat_json}" "${runtime_vars}"
printf "[cleanup_runner]\nlocalhost ansible_connection=local\n" > "${inventory_file}"

args=(ansible-playbook -i "${inventory_file}" -D "${repo_root}/ansible/playbooks/cleanup_expired_cloud_dev_desktops.yml" -e "@${runtime_vars}" -e "cloud_vm_request_validation_mode=cleanup")
if [[ "${mode}" == "dry-run" ]]; then
  args=(ansible-playbook -i "${inventory_file}" -D -C "${repo_root}/ansible/playbooks/cleanup_expired_cloud_dev_desktops.yml" -e "@${runtime_vars}" -e "cloud_vm_request_validation_mode=cleanup")
fi
ANSIBLE_CONFIG="${repo_root}/ansible/ansible.cfg" "${args[@]}"
