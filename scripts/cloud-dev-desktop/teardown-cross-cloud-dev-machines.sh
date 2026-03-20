#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: teardown-cross-cloud-dev-machines.sh \
  [--windows-request <path>] \
  [--fedora-request <path>] \
  [--kde-request <path>] \
  [--mode <park|destroy>] \
  [--dry-run]
EOF
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
windows_request="${repo_root}/ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml"
fedora_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml"
kde_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.ubuntu-kde.example.yml"
destroy_mode="destroy"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --windows-request) windows_request="$2"; shift 2 ;;
    --fedora-request) fedora_request="$2"; shift 2 ;;
    --kde-request) kde_request="$2"; shift 2 ;;
    --mode) destroy_mode="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done

[[ "${destroy_mode}" == "park" || "${destroy_mode}" == "destroy" ]] || usage

run_destroy() {
  local provider="$1"
  local request="$2"
  local cmd=(bash "${repo_root}/scripts/cloud-dev-desktop/destroy.sh" --provider "${provider}" --request "${request}" --mode "${destroy_mode}")
  if [[ "${dry_run}" == "true" ]]; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}"
}

echo "==> ${destroy_mode}: GCP Fedora GNOME desktop"
run_destroy gcp "${fedora_request}"

echo "==> ${destroy_mode}: GCP Ubuntu KDE desktop"
run_destroy gcp "${kde_request}"

echo "==> ${destroy_mode}: Azure Windows desktop"
run_destroy azure "${windows_request}"

cat <<EOF
Completed mode: ${destroy_mode}
Order: GCP Fedora GNOME -> GCP Ubuntu KDE -> Azure Windows
EOF
