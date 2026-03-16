#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
secret_vars_file="$(mktemp)"
runtime_vars_file="$(mktemp)"

python3 "${script_dir}/materialize-ansible-vars.py" \
  "${secret_vars_file}" \
  "${runtime_vars_file}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "secret_vars_file=${secret_vars_file}"
    echo "runtime_vars_file=${runtime_vars_file}"
  } >> "${GITHUB_OUTPUT}"
else
  cat <<EOF
secret_vars_file=${secret_vars_file}
runtime_vars_file=${runtime_vars_file}
EOF
fi
