#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 7 ]]; then
  echo "usage: $0 <service> <track> <repo-owner> <inventory-path> <workspace-path> <services-path> <repositories-path>" >&2
  exit 1
fi

service="$1"
track="$2"
repo_owner="$3"
inventory_path="$4"
workspace_path="$5"
services_path="$6"
repositories_path="$7"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${script_dir}/release-service-metadata.py" \
  "${service}" \
  "${track}" \
  "${repo_owner}" \
  "${inventory_path}" \
  "${workspace_path}" \
  "${services_path}" \
  "${repositories_path}"
