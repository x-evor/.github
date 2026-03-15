#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <service> <repo-owner> <inventory-path>" >&2
  exit 1
fi

service="$1"
repo_owner="$2"
inventory_path="$3"

server_alias="$(awk '
  /^\[server\]/ { in_server=1; next }
  /^\[/ { in_server=0 }
  in_server && NF > 0 && $1 !~ /^#/ { print $1; exit }
' "$inventory_path")"

if [[ -z "${server_alias}" ]]; then
  echo "failed to resolve first server alias from ${inventory_path}" >&2
  exit 1
fi

deploy_hostname="${server_alias%%.*}"

case "$service" in
  accounts)
    repo_name="accounts.svc.plus"
    playbook_path="ansible/playbooks/deploy_accounts_compose.yml"
    dockerfile_path="Dockerfile"
    build_context="."
    image_name="accounts"
    deploy_subdomain_prefix="accounts"
    stable_domain="accounts.svc.plus"
    host_port="18080"
    healthcheck_path="/healthz"
    ;;
  accounts-preview)
    repo_name="accounts.svc.plus"
    playbook_path="ansible/playbooks/deploy_accounts_compose.yml"
    dockerfile_path="Dockerfile"
    build_context="."
    image_name="accounts-preview"
    deploy_subdomain_prefix="accounts-preview"
    stable_domain="accounts-preview.svc.plus"
    host_port="18081"
    healthcheck_path="/healthz"
    ;;
  rag-server)
    repo_name="rag-server.svc.plus"
    playbook_path="ansible/playbooks/deploy_rag_server_compose.yml"
    dockerfile_path="Dockerfile"
    build_context="."
    image_name="rag-server"
    deploy_subdomain_prefix="rag-server"
    stable_domain="rag-server.svc.plus"
    host_port="18082"
    healthcheck_path="/healthz"
    ;;
  x-cloud-flow)
    repo_name="x-cloud-flow.svc.plus"
    playbook_path="ansible/playbooks/deploy_x_cloud_flow_compose.yml"
    dockerfile_path="Dockerfile"
    build_context="."
    image_name="x-cloud-flow"
    deploy_subdomain_prefix="x-cloud-flow"
    stable_domain="x-cloud-flow.svc.plus"
    host_port="18083"
    healthcheck_path="/healthz"
    ;;
  x-ops-agent)
    repo_name="x-ops-agent.svc.plus"
    playbook_path="ansible/playbooks/deploy_x_ops_agent_compose.yml"
    dockerfile_path="Dockerfile"
    build_context="."
    image_name="x-ops-agent"
    deploy_subdomain_prefix="x-ops-agent"
    stable_domain="x-ops-agent.svc.plus"
    host_port="18084"
    healthcheck_path="/healthz"
    ;;
  x-scope-hub)
    repo_name="x-scope-hub.svc.plus"
    playbook_path="ansible/playbooks/deploy_x_scope_hub_compose.yml"
    dockerfile_path="mcp-server/Dockerfile"
    build_context="."
    image_name="x-scope-hub"
    deploy_subdomain_prefix="x-scope-hub"
    stable_domain="x-scope-hub.svc.plus"
    host_port="18085"
    healthcheck_path="/manifest"
    ;;
  *)
    echo "unsupported service: ${service}" >&2
    exit 1
    ;;
esac

cat <<EOF
repo_owner=${repo_owner}
repo_name=${repo_name}
service_repository=${repo_owner}/${repo_name}
service_checkout_path=${repo_name}
playbook_path=${playbook_path}
dockerfile_path=${dockerfile_path}
build_context=${build_context}
image_name=${image_name}
deploy_subdomain_prefix=${deploy_subdomain_prefix}
stable_domain=${stable_domain}
host_port=${host_port}
healthcheck_path=${healthcheck_path}
deploy_server_alias=${server_alias}
deploy_hostname=${deploy_hostname}
EOF

