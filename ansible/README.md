# Single-Node Compose Migration

This directory contains the shared Ansible building blocks for migrating Cloud Run
services to the single-node Docker Compose host defined in `inventory.ini`.

Workflow usage reference:

- `docs/operations-governance/service-release-control-plane-workflow.md`

## Shared Pieces

- `roles/shared_compose_service_deploy/`
  - Renders per-release Docker Compose files and app env files.
  - Writes the matching Caddy site file to `/etc/caddy/conf.d/`.
  - Brings up the new release and retires older releases for the same logical service.
- `playbooks/update_cloudflare_dns.yml`
  - Reusable DNS automation for `svc.plus`.
  - Accepts either `CLOUDFLARE_API_TOKEN` or `CLOUDFLARE_DNS_API_TOKEN`.

## Migration Order

1. Verify the image build for the service repository and push it to `ghcr.io`.
2. Update the release DNS record:
   - `<server-name>-<deploy-hostname>-<git-short-commit-id>.svc.plus`
   - Reuse `ansible/playbooks/update_cloudflare_dns.yml` from this control-plane repo.
3. Run a dry-run with diff from the service repository:
   - `GIT_SHORT_COMMIT="$(git rev-parse --short HEAD)" ansible-playbook -D -C ansible/playbooks/<playbook>.yml -e @/secure/path/<service>.vault.yml`
4. Apply the deployment:
   - `GIT_SHORT_COMMIT="$(git rev-parse --short HEAD)" ansible-playbook -D ansible/playbooks/<playbook>.yml -e @/secure/path/<service>.vault.yml`
5. After validating the new release on the deploy domain, manually switch the stable entry domain CNAME to the release domain.

## Secret Handling

- Do not commit real tokens or passwords to Git.
- Keep the real variable file outside the repository, or use `ansible-vault`.
- Passing secrets from executor environment variables is also valid.
- If a vault sidecar/agent is available, resolve secrets before invoking `ansible-playbook`.

## GitHub Actions Secrets

- `GHCR_USERNAME`
- `GHCR_TOKEN`
- `CLOUDFLARE_DNS_API_TOKEN`
- `WORKSPACE_REPO_TOKEN` (optional fallback when `GITHUB_TOKEN` cannot read sibling repos)
- `ACCOUNTS_ANSIBLE_VARS_YAML`
- `RAG_SERVER_ANSIBLE_VARS_YAML`
- `X_CLOUD_FLOW_ANSIBLE_VARS_YAML`
- `X_OPS_AGENT_ANSIBLE_VARS_YAML`
- `X_SCOPE_HUB_ANSIBLE_VARS_YAML`
- `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`

## GitHub Actions Variables

- `SINGLE_NODE_VPS_SSH_HOST`
- `SINGLE_NODE_VPS_SSH_USER`
- `SINGLE_NODE_VPS_SSH_PORT`
- `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS`

## Example DNS Update

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit

export CLOUDFLARE_DNS_API_TOKEN="..."

ansible-playbook ansible/playbooks/update_cloudflare_dns.yml \
  -e '{"cloudflare_dns_records":[{"type":"CNAME","name":"accounts-us-xhttp-abc1234.svc.plus","content":"us-xhttp.svc.plus","proxied":false}]}'
```
