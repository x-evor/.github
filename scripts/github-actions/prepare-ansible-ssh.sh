#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <server-alias>" >&2
  exit 1
fi

server_alias="$1"

: "${SINGLE_NODE_VPS_SSH_PRIVATE_KEY:?SINGLE_NODE_VPS_SSH_PRIVATE_KEY is required}"

ssh_host="${SINGLE_NODE_VPS_SSH_HOST:-${server_alias}}"
ssh_user="${SINGLE_NODE_VPS_SSH_USER:-root}"
ssh_port="${SINGLE_NODE_VPS_SSH_PORT:-22}"
ssh_known_hosts="${SINGLE_NODE_VPS_SSH_KNOWN_HOSTS:-}"

ssh_dir="${HOME}/.ssh"
private_key_file="${ssh_dir}/id_deploy"
known_hosts_file="${ssh_dir}/known_hosts"
inventory_file="$(mktemp)"

umask 077
mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

normalized_private_key="$(
  python3 - <<'PY'
import base64
import os
import sys

raw = os.environ["SINGLE_NODE_VPS_SSH_PRIVATE_KEY"].replace("\r", "").strip()

def strip_outer_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1].strip()
    return value

raw = strip_outer_quotes(raw)
candidates = [raw]

if "\\n" in raw:
    candidates.append(strip_outer_quotes(raw.replace("\\n", "\n").strip()))

try:
    decoded = base64.b64decode(raw, validate=True).decode("utf-8").replace("\r", "").strip()
except Exception:
    decoded = ""

if decoded:
    candidates.append(strip_outer_quotes(decoded))

for candidate in candidates:
    if "BEGIN " in candidate and "PRIVATE KEY" in candidate:
        sys.stdout.write(candidate.rstrip("\n") + "\n")
        raise SystemExit(0)

sys.stdout.write(raw.rstrip("\n") + "\n")
PY
)"

printf '%s' "${normalized_private_key}" > "${private_key_file}"
chmod 600 "${private_key_file}"

if ! ssh-keygen -y -f "${private_key_file}" >/dev/null 2>&1; then
  payload_hint="$(
    python3 - <<'PY'
import os

raw = os.environ["SINGLE_NODE_VPS_SSH_PRIVATE_KEY"].replace("\r", "").strip()
trimmed = raw.strip("'\"").strip()

if trimmed.startswith("ssh-rsa ") or trimmed.startswith("ssh-ed25519 ") or trimmed.startswith("ecdsa-sha2-"):
    print("looks like a public key, not a private key")
elif trimmed.startswith("~/.ssh/") or trimmed.startswith("/") or trimmed.endswith(".pem") or trimmed.endswith("id_rsa"):
    print("looks like a filesystem path, not file contents")
elif "BEGIN " in trimmed and "PRIVATE KEY" in trimmed:
    print("contains private-key markers but failed ssh-keygen validation")
elif "\\n" in raw:
    print("contains escaped newlines but did not normalize to a valid private key")
else:
    print("does not look like a supported private key payload")
PY
  )"
  echo "Invalid SINGLE_NODE_VPS_SSH_PRIVATE_KEY payload: ${payload_hint}" >&2
  exit 1
fi

if [[ -n "${ssh_known_hosts}" ]]; then
  printf '%s\n' "${ssh_known_hosts}" > "${known_hosts_file}"
else
  ssh-keyscan -p "${ssh_port}" -H "${ssh_host}" > "${known_hosts_file}"
fi
chmod 644 "${known_hosts_file}"

cat > "${inventory_file}" <<EOF
[server]
${server_alias} ansible_host=${ssh_host} ansible_user=${ssh_user}

[all:vars]
ansible_port=${ssh_port}
ansible_user=${ssh_user}
ansible_ssh_private_key_file=${private_key_file}
ansible_host_key_checking=True
ansible_ssh_common_args=-o UserKnownHostsFile=${known_hosts_file}
EOF

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "inventory_file=${inventory_file}"
    echo "private_key_file=${private_key_file}"
    echo "known_hosts_file=${known_hosts_file}"
  } >> "${GITHUB_OUTPUT}"
else
  cat <<EOF
inventory_file=${inventory_file}
private_key_file=${private_key_file}
known_hosts_file=${known_hosts_file}
EOF
fi
