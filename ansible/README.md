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

- `GHCR_TOKEN`
- `CLOUDFLARE_DNS_API_TOKEN`
- `WORKSPACE_REPO_TOKEN` (optional fallback when `GITHUB_TOKEN` cannot read sibling repos)
- `INTERNAL_SERVICE_TOKEN`
- `ACCOUNTS_DB_PASSWORD`
- `ACCOUNTS_SMTP_PASSWORD`
- `RAG_SERVER_ANSIBLE_VARS_YAML`
- `X_CLOUD_FLOW_ANSIBLE_VARS_YAML`
- `X_OPS_AGENT_ANSIBLE_VARS_YAML`
- `X_SCOPE_HUB_ANSIBLE_VARS_YAML`
- `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`

`GHCR_USERNAME` is not stored as a secret. It is defined in the workflow env and should match the GitHub user that owns `GHCR_TOKEN`.

`accounts.svc.plus` public release defaults live in `subrepos/accounts.svc.plus/ansible/vars/accounts.release.public.yml`; only `INTERNAL_SERVICE_TOKEN`, `ACCOUNTS_DB_PASSWORD`, and `ACCOUNTS_SMTP_PASSWORD` are expected in GitHub Secrets.

## Workflow SSH Defaults

- `SINGLE_NODE_VPS_SSH_HOST=5.78.45.49`
- `SINGLE_NODE_VPS_SSH_USER=root`
- `SINGLE_NODE_VPS_SSH_PORT=22`
- `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS=` (empty by default)

Manual `workflow_dispatch` runs may override those values with optional inputs:

- `ssh_host`
- `ssh_user`
- `ssh_port`
- `ssh_known_hosts`

## Example DNS Update

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit

export CLOUDFLARE_DNS_API_TOKEN="..."

ansible-playbook ansible/playbooks/update_cloudflare_dns.yml \
  -e '{"cloudflare_dns_records":[{"type":"CNAME","name":"accounts-us-xhttp-abc1234.svc.plus","content":"us-xhttp.svc.plus","proxied":false}]}'
```

## Cloud Dev Desktop Control Plane

The repo also ships a separate control-plane slice for temporary Azure/GCP
desktop VMs used for app development and testing.

See:

- `ansible/README-cloud-dev-desktop.md`
- `ansible/playbooks/create_cloud_dev_desktop.yml`
- `ansible/playbooks/bootstrap_cloud_dev_desktop.yml`
- `ansible/playbooks/verify_cloud_dev_desktop.yml`
- `ansible/playbooks/destroy_cloud_dev_desktop.yml`
- `ansible/playbooks/cleanup_expired_cloud_dev_desktops.yml`
