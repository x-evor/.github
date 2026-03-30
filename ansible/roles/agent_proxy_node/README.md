# agent_proxy_node

Reusable Ansible role for provisioning an `agent.svc.plus`-style proxy node.

This role wraps the upstream `setup-proxy.sh` flow and keeps the deployment
entrypoint inside the control repo.

## Defaults

- `agent_proxy_domain`
- `agent_proxy_target_ip`
- `agent_proxy_script_url`
- `agent_proxy_script_path`
- `agent_proxy_auth_url`
- `agent_proxy_internal_service_token`
- `agent_proxy_open_stunnel_5443`
- `agent_proxy_upgrade_only`
- `agent_proxy_standalone`

## Expectations

- `agent_proxy_internal_service_token` is required unless `agent_proxy_standalone=true`.
- The target host inventory record must point to `agent_proxy_target_ip`.
- DNS is handled separately by the `cloudflare_dns` role.

## Usage

Use the matching playbook under `ansible/playbooks/` and override only the
target domain or token values when needed.
