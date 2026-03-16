#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 8 ]]; then
  echo "usage: $0 <service> <track> <repo-owner> <control-repo-dir> <inventory-path> <workspace-path> <services-common-path> <repositories-path>" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
metadata="$("${script_dir}/release-service-metadata.sh" "$@")"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  while IFS='=' read -r key value; do
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  done <<< "${metadata}"
else
  printf '%s\n' "${metadata}"
fi
