#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 8 ]]; then
  echo "usage: $0 <service> <track> <repo-owner> <control-repo-dir> <inventory-path> <workspace-path> <services-path> <repositories-path>" >&2
  exit 1
fi

service="$1"
track="$2"
repo_owner="$3"
control_repo_dir="$4"
inventory_path="$5"
workspace_path="$6"
services_path="$7"
repositories_path="$8"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${script_dir}/release-service-metadata.py" \
  "${service}" \
  "${track}" \
  "${repo_owner}" \
  "${control_repo_dir}" \
  "${inventory_path}" \
  "${workspace_path}" \
  "${services_path}" \
  "${repositories_path}"
