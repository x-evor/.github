#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <control-repo-dir> <release-domain> <deploy-server-alias>" >&2
  exit 1
fi

control_repo_dir="$1"
release_domain="$2"
deploy_server_alias="$3"

export RELEASE_DOMAIN="${release_domain}"
export DEPLOY_SERVER_ALIAS="${deploy_server_alias}"
dns_payload="$(python -c 'import json, os; print(json.dumps({"cloudflare_dns_records":[{"type":"CNAME","name":os.environ["RELEASE_DOMAIN"],"content":os.environ["DEPLOY_SERVER_ALIAS"],"ttl":1,"proxied":False}]}))')"

cd "${control_repo_dir}"
ansible-playbook ansible/playbooks/update_cloudflare_dns.yml -e "${dns_payload}"
