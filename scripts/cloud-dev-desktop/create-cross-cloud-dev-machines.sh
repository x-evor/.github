#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: create-cross-cloud-dev-machines.sh \
  [--windows-request <path>] \
  [--fedora-request <path>] \
  [--kde-request <path>] \
  [--dry-run]
EOF
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state_root="${repo_root}/.ansible/cloud-dev-desktop"
runtime_root="${state_root}/runtime"
keys_root="${state_root}/keys"

windows_request="${repo_root}/ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml"
fedora_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml"
kde_request="${repo_root}/ansible/vars/cloud_dev_desktop.gcp.ubuntu-kde.example.yml"
mode="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --windows-request) windows_request="$2"; shift 2 ;;
    --fedora-request) fedora_request="$2"; shift 2 ;;
    --kde-request) kde_request="$2"; shift 2 ;;
    --dry-run) mode="dry-run"; shift ;;
    *) usage ;;
  esac
done

mkdir -p "${runtime_root}" "${keys_root}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd python3
require_cmd ssh-keygen

run_wrapper() {
  local action="$1"
  local provider="$2"
  local request="$3"
  local cmd=(bash "${repo_root}/scripts/cloud-dev-desktop/${action}.sh" --provider "${provider}" --request "${request}")
  if [[ "${mode}" == "dry-run" ]]; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}"
}

json_query() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data
for key in expr.split("."):
    if not key:
        continue
    value = value[key]
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

yaml_query() {
  local path="$1"
  local key="$2"
  python3 - "$path" "$key" <<'PY'
import sys
import yaml

path, key = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
value = data
for part in key.split("."):
    value = value[part]
print(value)
PY
}

render_overlay_request() {
  local base_request="$1"
  local overlay_json="$2"
  local output_path="$3"
  python3 - "$base_request" "$overlay_json" "$output_path" <<'PY'
import json
import sys
from copy import deepcopy

import yaml

base_path, overlay_path, output_path = sys.argv[1:4]

def merge(left, right):
    result = deepcopy(left)
    for key, value in (right or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = value
    return result

with open(base_path, "r", encoding="utf-8") as handle:
    base = yaml.safe_load(handle) or {}
with open(overlay_path, "r", encoding="utf-8") as handle:
    overlay = json.load(handle) or {}
merged = merge(base, overlay)
with open(output_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(merged, handle, sort_keys=False)
PY
}

windows_profile="$(yaml_query "${windows_request}" profile_name)"
fedora_profile="$(yaml_query "${fedora_request}" profile_name)"
kde_profile="$(yaml_query "${kde_request}" profile_name)"
windows_admin="$(yaml_query "${windows_request}" admin_username)"

windows_state="${state_root}/azure-${windows_profile}.json"
fedora_state="${state_root}/gcp-${fedora_profile}.json"
kde_state="${state_root}/gcp-${kde_profile}.json"

fleet_key_base="${keys_root}/${windows_profile}-to-gcp"
if [[ ! -f "${fleet_key_base}" ]]; then
  ssh-keygen -t ed25519 -N "" -C "${windows_profile}-gcp-fleet" -f "${fleet_key_base}" >/dev/null
fi

fleet_public_key="$(<"${fleet_key_base}.pub")"
fleet_private_key_b64="$(base64 < "${fleet_key_base}" | tr -d '\n')"
fleet_public_key_b64="$(base64 < "${fleet_key_base}.pub" | tr -d '\n')"
windows_public_ip="198.51.100.10"

if [[ "${mode}" != "dry-run" ]]; then
  echo "==> Creating Azure Windows desktop"
  run_wrapper create azure "${windows_request}"

  if [[ ! -f "${windows_state}" ]]; then
    echo "missing Windows state file: ${windows_state}" >&2
    exit 1
  fi

  windows_public_ip="$(json_query "${windows_state}" public_ip)"
else
  echo "==> Dry-run: using placeholder Windows public IP ${windows_public_ip}"
fi

windows_cidr="${windows_public_ip}/32"

fedora_overlay_json="$(mktemp "${runtime_root}/fedora-overlay.XXXXXX.json")"
fedora_runtime_request="${runtime_root}/$(basename "${fedora_request%.yml}")-runtime.yml"
cat > "${fedora_overlay_json}" <<EOF
{
  "allowed_cidrs": $(python3 - "${fedora_request}" "${windows_cidr}" <<'PY'
import json
import sys
import yaml

path, cidr = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
cidrs = list(data.get("allowed_cidrs") or [])
if cidr not in cidrs:
    cidrs.append(cidr)
print(json.dumps(cidrs))
PY
),
  "ssh_public_key_path": $(python3 - "${fleet_key_base}.pub" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
),
  "cloud_dev_desktop_extra_authorized_keys": [$(python3 - "${fleet_public_key}" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
)]
}
EOF
render_overlay_request "${fedora_request}" "${fedora_overlay_json}" "${fedora_runtime_request}"

kde_overlay_json="$(mktemp "${runtime_root}/kde-overlay.XXXXXX.json")"
kde_runtime_request="${runtime_root}/$(basename "${kde_request%.yml}")-runtime.yml"
cat > "${kde_overlay_json}" <<EOF
{
  "allowed_cidrs": $(python3 - "${kde_request}" "${windows_cidr}" <<'PY'
import json
import sys
import yaml

path, cidr = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
cidrs = list(data.get("allowed_cidrs") or [])
if cidr not in cidrs:
    cidrs.append(cidr)
print(json.dumps(cidrs))
PY
),
  "ssh_public_key_path": $(python3 - "${fleet_key_base}.pub" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
),
  "cloud_dev_desktop_extra_authorized_keys": [$(python3 - "${fleet_public_key}" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
)]
}
EOF
render_overlay_request "${kde_request}" "${kde_overlay_json}" "${kde_runtime_request}"

if [[ "${mode}" == "dry-run" ]]; then
  echo "==> Dry-run: validating create flow for Azure Windows desktop"
  run_wrapper create azure "${windows_request}"
  echo "==> Dry-run: validating create flow for GCP Fedora GNOME desktop"
  run_wrapper create gcp "${fedora_runtime_request}"
  echo "==> Dry-run: validating create flow for GCP Ubuntu KDE desktop"
  run_wrapper create gcp "${kde_runtime_request}"
  cat <<EOF
Dry-run completed.
Rendered Fedora runtime request: ${fedora_runtime_request}
Rendered KDE runtime request: ${kde_runtime_request}
Fleet SSH key (generated locally only): ${fleet_key_base}
Planned Windows SSH aliases: gcp-fedora-gnome, gcp-ubuntu-kde
EOF
  exit 0
fi

echo "==> Creating GCP Fedora GNOME desktop"
run_wrapper create gcp "${fedora_runtime_request}"
echo "==> Bootstrapping GCP Fedora GNOME desktop"
run_wrapper bootstrap gcp "${fedora_runtime_request}"
echo "==> Verifying GCP Fedora GNOME desktop"
run_wrapper verify gcp "${fedora_runtime_request}"

echo "==> Creating GCP Ubuntu KDE desktop"
run_wrapper create gcp "${kde_runtime_request}"
echo "==> Bootstrapping GCP Ubuntu KDE desktop"
run_wrapper bootstrap gcp "${kde_runtime_request}"
echo "==> Verifying GCP Ubuntu KDE desktop"
run_wrapper verify gcp "${kde_runtime_request}"

if [[ ! -f "${fedora_state}" || ! -f "${kde_state}" ]]; then
  echo "missing Linux state file(s): ${fedora_state} ${kde_state}" >&2
  exit 1
fi

fedora_ip="$(json_query "${fedora_state}" public_ip)"
fedora_user="$(json_query "${fedora_state}" admin_username)"
kde_ip="$(json_query "${kde_state}" public_ip)"
kde_user="$(json_query "${kde_state}" admin_username)"

windows_ssh_config="$(mktemp "${runtime_root}/windows-ssh-config.XXXXXX")"
cat > "${windows_ssh_config}" <<EOF
Host gcp-fedora-gnome
  HostName ${fedora_ip}
  User ${fedora_user}
  Port 22
  IdentityFile C:/Users/${windows_admin}/.ssh/${windows_profile}-to-gcp
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30

Host gcp-ubuntu-kde
  HostName ${kde_ip}
  User ${kde_user}
  Port 22
  IdentityFile C:/Users/${windows_admin}/.ssh/${windows_profile}-to-gcp
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
EOF

windows_overlay_json="$(mktemp "${runtime_root}/windows-overlay.XXXXXX.json")"
windows_runtime_request="${runtime_root}/$(basename "${windows_request%.yml}")-runtime.yml"
cat > "${windows_overlay_json}" <<EOF
{
  "windows_ssh_private_key_b64": $(python3 - "${fleet_private_key_b64}" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
),
  "windows_ssh_public_key_b64": $(python3 - "${fleet_public_key_b64}" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
),
  "windows_ssh_config_b64": $(python3 - "${windows_ssh_config}" <<'PY'
import base64
import json
import sys
with open(sys.argv[1], "rb") as handle:
    print(json.dumps(base64.b64encode(handle.read()).decode("ascii")))
PY
),
  "windows_ssh_host_aliases": ["gcp-fedora-gnome", "gcp-ubuntu-kde"],
  "windows_ssh_identity_filename": $(python3 - "${windows_profile}-to-gcp" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
)
}
EOF
render_overlay_request "${windows_request}" "${windows_overlay_json}" "${windows_runtime_request}"

echo "==> Bootstrapping Azure Windows desktop"
run_wrapper bootstrap azure "${windows_runtime_request}"
echo "==> Verifying Azure Windows desktop"
run_wrapper verify azure "${windows_runtime_request}"

cat <<EOF
Windows state: ${windows_state}
Fedora state: ${fedora_state}
KDE state: ${kde_state}
Fleet SSH key: ${fleet_key_base}
Rendered Windows runtime request: ${windows_runtime_request}
Windows SSH aliases: gcp-fedora-gnome, gcp-ubuntu-kde
EOF
