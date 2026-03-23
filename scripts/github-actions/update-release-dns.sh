#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]] || [[ $# -gt 4 ]]; then
  echo "usage: $0 <control-repo-path> <release-domain> <deploy-server-alias> [stable-domain]" >&2
  exit 1
fi

control_repo_path="$1"
release_domain="$2"
deploy_server_alias="$3"
stable_domain="${4:-}"

export RELEASE_DOMAIN="${release_domain}"
export DEPLOY_SERVER_ALIAS="${deploy_server_alias}"
export STABLE_DOMAIN="${stable_domain}"

# Build DNS records: release domain CNAME to server, and optionally stable domain CNAME to release domain
if [[ -n "${stable_domain}" ]]; then
  dns_payload="$(python -c 'import json, os; records=[{"type":"CNAME","name":os.environ["RELEASE_DOMAIN"],"content":os.environ["DEPLOY_SERVER_ALIAS"],"ttl":1,"proxied":False},{"type":"CNAME","name":os.environ["STABLE_DOMAIN"],"content":os.environ["RELEASE_DOMAIN"],"ttl":1,"proxied":False}]; print(json.dumps({"cloudflare_dns_records":records}))')"
else
  dns_payload="$(python -c 'import json, os; print(json.dumps({"cloudflare_dns_records":[{"type":"CNAME","name":os.environ["RELEASE_DOMAIN"],"content":os.environ["DEPLOY_SERVER_ALIAS"],"ttl":1,"proxied":False}]}))')"
fi

cd "${control_repo_path}"
ansible-playbook ansible/playbooks/update_cloudflare_dns.yml -e "${dns_payload}"
