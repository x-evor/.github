#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0" >&2
  exit 1
}

[[ $# -eq 0 ]] || usage

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playbooks_root="$(cd "${repo_root}/../playbooks" && pwd)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[missing] $1" >&2
    exit 1
  }
  echo "[ok] $1 -> $(command -v "$1")"
}

require_cmd python3
require_cmd ansible-playbook
require_cmd ssh-keygen
require_cmd az
require_cmd gcloud

echo "[check] Azure CLI session"
az account show --query '{subscription:id,user:user.name}' -o json

echo "[check] GCP CLI session"
gcloud auth list --filter=status:ACTIVE --format='json(account,status)'

echo "[check] Ansible syntax"
ANSIBLE_CONFIG="${playbooks_root}/ansible.cfg" ansible-playbook --syntax-check -i 'localhost,' -c local "${playbooks_root}/bootstrap_cloud_dev_desktop.yml" -e @ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml >/dev/null

echo "[ok] local cloud dev desktop precheck passed"
