#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: parity-release.sh \
  --action <provision|brief|status|park|destroy> \
  [--manifest <path>] \
  [--windows-request <path>] \
  [--fedora-request <path>] \
  [--kde-request <path>] \
  [--output <path>] \
  [--dry-run]
EOF
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state_root="${repo_root}/.ansible/cloud-dev-desktop"
runtime_root="${state_root}/runtime"

action=""
manifest="${repo_root}/ansible/vars/cloud_dev_desktop.parity_release.example.yml"
windows_request="${repo_root}/ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml"
fedora_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml"
kde_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.ubuntu-kde.example.yml"
output_path="${runtime_root}/parity-release-brief.md"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) action="$2"; shift 2 ;;
    --manifest) manifest="$2"; shift 2 ;;
    --windows-request) windows_request="$2"; shift 2 ;;
    --fedora-request) fedora_request="$2"; shift 2 ;;
    --kde-request) kde_request="$2"; shift 2 ;;
    --output) output_path="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done

[[ -n "${action}" ]] || usage

run_with_optional_dry_run() {
  local cmd=("$@")
  if [[ "${dry_run}" == "true" ]]; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}"
}

render_brief() {
  mkdir -p "${runtime_root}"
  python3 "${repo_root}/scripts/cloud-dev-desktop/render-parity-release-brief.py" \
    --manifest "${manifest}" \
    --state-root "${state_root}" \
    --output "${output_path}"
}

case "${action}" in
  provision)
    run_with_optional_dry_run \
      bash "${repo_root}/scripts/cloud-dev-desktop/create-cross-cloud-dev-machines.sh" \
      --windows-request "${windows_request}" \
      --fedora-request "${fedora_request}" \
      --kde-request "${kde_request}"
    render_brief
    ;;
  brief|status)
    render_brief
    ;;
  park)
    run_with_optional_dry_run \
      bash "${repo_root}/scripts/cloud-dev-desktop/teardown-cross-cloud-dev-machines.sh" \
      --windows-request "${windows_request}" \
      --fedora-request "${fedora_request}" \
      --kde-request "${kde_request}" \
      --mode park
    ;;
  destroy)
    run_with_optional_dry_run \
      bash "${repo_root}/scripts/cloud-dev-desktop/teardown-cross-cloud-dev-machines.sh" \
      --windows-request "${windows_request}" \
      --fedora-request "${fedora_request}" \
      --kde-request "${kde_request}" \
      --mode destroy
    ;;
  *)
    usage
    ;;
esac
