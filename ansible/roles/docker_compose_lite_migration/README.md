# docker_compose_lite_migration

Ansible role for the lightweight single-VPS migration path:

- `accounts`
- `rag-server`
- `APISIX` standalone
- shared `stunnel-client`

This role is designed for cheap-model test runs and manual VPS verification.

## Run

```bash
# Dry-run (preview only)
ansible-playbook -i ansible/inventory.ini \
  -e "docker_compose_lite_apply=false" \
  ansible/playbooks/deploy_docker_compose_lite_migration.yml --check

# Or use the shorthand (defaults apply=false when using --check)
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/deploy_docker_compose_lite_migration.yml -C
```

## What it does

1. **Render** - Renders Docker Compose stack files to the target host
2. **Diff** - Runs `docker compose config` as preview
3. **Apply** - Deploys the stack only when not in check mode and `docker_compose_lite_apply=true`
4. **Verify** - Runs lightweight verification commands

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `docker_compose_lite_apply` | Enable actual deployment | `true` |
| `docker_compose_lite_project_dir` | Target directory on host | `/opt/cloud-neutral/docker-compose-lite` |
| `docker_compose_lite_project_name` | Compose project name | `cn-toolkit-lite` |
| `docker_compose_lite_accounts_image` | Accounts service image | (required) |
| `docker_compose_lite_rag_image` | RAG server image | (required) |
| `docker_compose_lite_dns_provider` | DNS provider (cloudflare/aliyun/dnspod) | (empty) |

## Verification

After deployment, verify with:

```bash
# On the target host
bash /opt/cloud-neutral/docker-compose-lite/verify_stack.sh

# Or via Ansible
ansible -i ansible/inventory.ini all -a "docker ps --filter name=cn-toolkit-"
```
