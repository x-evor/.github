#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <mode> <inventory-file> <playbook-path> <public-vars-path> <secret-vars-file> <runtime-vars-file>" >&2
  exit 1
fi

mode="$1"
inventory_file="$2"
playbook_path="$3"
public_vars_path="$4"
secret_vars_file="$5"
runtime_vars_file="$6"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
merged_vars_file="$(mktemp)"

cleanup() {
  rm -f "${merged_vars_file}"
}
trap cleanup EXIT

args=(
  ansible-playbook
  -i "${inventory_file}"
  -D
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

args+=("${playbook_path}")

merge_inputs=()
if [[ -n "${public_vars_path}" ]]; then
  merge_inputs+=("${public_vars_path}")
fi
merge_inputs+=("${secret_vars_file}" "${runtime_vars_file}")

python3 "${script_dir}/merge-ansible-vars.py" "${merged_vars_file}" "${merge_inputs[@]}"

args+=(
  -e "@${merged_vars_file}"
)

ANSIBLE_SSH_ARGS='-o ControlMaster=no -o ControlPersist=no' "${args[@]}"
