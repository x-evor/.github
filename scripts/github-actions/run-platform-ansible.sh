#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <mode> <inventory-file> <playbook-path> <vars-file> <target-host> <inventory-template>" >&2
  exit 1
fi

mode="$1"
inventory_file="$2"
playbook_path="$3"
vars_file="$4"
target_host="$5"
inventory_template="$6"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_path="$(dirname "$(dirname "${script_dir}")")"

prepare_output="$(mktemp)"
trap 'rm -f "${prepare_output}"' EXIT

bash "${script_dir}/prepare-ansible-runtime.sh" \
  "${inventory_file}" \
  "${target_host}" \
  "${inventory_template}" > "${prepare_output}"

runtime_inventory="$(awk -F= '/^inventory_file=/{print $2}' "${prepare_output}")"
if [[ -z "${runtime_inventory}" ]]; then
  echo "prepare-ansible-runtime did not emit inventory_file" >&2
  exit 1
fi

args=(
  ansible-playbook
  -i "${runtime_inventory}"
  -D
  "${playbook_path}"
  -e "@${vars_file}"
)

case "${mode}" in
  dry-run)
    args+=(-C)
    ;;
  apply)
    ;;
  *)
    echo "unknown mode: ${mode}" >&2
    exit 1
    ;;
esac

ANSIBLE_CONFIG="${control_repo_path}/ansible/ansible.cfg" \
ANSIBLE_SSH_ARGS='-o ControlMaster=no -o ControlPersist=no' \
"${args[@]}"
