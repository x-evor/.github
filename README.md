# Cloud-Neutral Toolkit Control Repo

This repository is the management hub for a multi-repo project under the `cloud-neutral-toolkit` org.

## Quick Start

- Open the workspace: `console.svc.plus.code-workspace`
- Read architecture and ownership: `docs/architecture/project-overview.md`
- Follow unified rules: `AGENTS.md` and `docs/operations-governance/governance.md`
- Run release flow from checklist: `docs/operations-governance/release-checklist.md`
- Track cross-repo work: `docs/operations-governance/cross-repo-tasks.md`

## Control Documents

- Project overview: [`docs/architecture/project-overview.md`](docs/architecture/project-overview.md)
- Agent operating rules: [`AGENTS.md`](AGENTS.md)
- Governance standard: [`docs/operations-governance/governance.md`](docs/operations-governance/governance.md)
- Release checklist: [`docs/operations-governance/release-checklist.md`](docs/operations-governance/release-checklist.md)
- Cross-repo task board: [`docs/operations-governance/cross-repo-tasks.md`](docs/operations-governance/cross-repo-tasks.md)
- Docs index: [`docs/README.md`](docs/README.md)
- Workspace file: [`console.svc.plus.code-workspace`](console.svc.plus.code-workspace)
- Env template: [`.env.example`](.env.example)
- Env/secret skill: [`skills/env-secrets-governance/SKILL.md`](skills/env-secrets-governance/SKILL.md)
- Root README skill: [`skills/readme-root-standard/SKILL.md`](skills/readme-root-standard/SKILL.md)
- Unified setup.sh skill: [`skills/unified-setup-sh/SKILL.md`](skills/unified-setup-sh/SKILL.md)
- Release branch policy skill: [`skills/release-branch-policy/SKILL.md`](skills/release-branch-policy/SKILL.md)

## Codex Working Pattern

For cross-repo requests, use one objective per task and require this output format:

1. Change Scope
2. Files Changed
3. Risk Points
4. Test Commands
5. Rollback Plan

## Repository Owner

- Current owner model: all listed repositories are owned/managed by `@shenlan`.
- Org dashboard: [cloud-neutral-toolkit dashboard](https://github.com/orgs/cloud-neutral-toolkit/dashboard)

## Notes

- Secrets stay in local `.env` (gitignored) and production secret managers.
- This repo holds standards and coordination docs, not service runtime code.

## Single-Node Release

This repo coordinates single-node VPS releases for the `svc.plus` services.

Reference docs:

- Ansible overview: [`ansible/README.md`](ansible/README.md)
- Workflow details: [`docs/operations-governance/single-node-service-release-workflow.md`](docs/operations-governance/single-node-service-release-workflow.md)

### Local Deploy Commands

Run these commands from the repository root:

1. Validate the control-plane playbooks:

```bash
ansible-playbook --syntax-check ansible/playbooks/update_cloudflare_dns.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/install_docker_engine.yml -D -C
```

2. Update the release DNS record:

```bash
export CLOUDFLARE_DNS_API_TOKEN="..."

ansible-playbook ansible/playbooks/update_cloudflare_dns.yml \
  -e '{"cloudflare_dns_records":[{"type":"CNAME","name":"accounts-us-xhttp-abc1234.svc.plus","content":"us-xhttp.svc.plus","proxied":false}]}'
```

3. Run the service-repo Ansible dry-run and apply:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/<service-repo>
export GIT_SHORT_COMMIT="$(git rev-parse --short HEAD)"

ansible-playbook -D -C ansible/playbooks/<service-playbook>.yml \
  -e @/secure/path/<service>.vault.yml \
  -e @/secure/path/<service>.runtime.yml

ansible-playbook -D ansible/playbooks/<service-playbook>.yml \
  -e @/secure/path/<service>.vault.yml \
  -e @/secure/path/<service>.runtime.yml
```

### GitHub Actions Manual Release

Workflow file:

- `.github/workflows/single_node_service_release.yml`

Service mapping:

| Service | Repo | Playbook | Workflow `service` |
| --- | --- | --- | --- |
| accounts | `accounts.svc.plus` | `ansible/playbooks/deploy_accounts_compose.yml` | `accounts` |
| accounts-preview | `accounts.svc.plus` | `ansible/playbooks/deploy_accounts_compose.yml` | `accounts-preview` |
| rag-server | `rag-server.svc.plus` | `ansible/playbooks/deploy_rag_server_compose.yml` | `rag-server` |
| x-cloud-flow | `x-cloud-flow.svc.plus` | `ansible/playbooks/deploy_x_cloud_flow_compose.yml` | `x-cloud-flow` |
| x-ops-agent | `x-ops-agent.svc.plus` | `ansible/playbooks/deploy_x_ops_agent_compose.yml` | `x-ops-agent` |
| x-scope-hub | `x-scope-hub.svc.plus` | `ansible/playbooks/deploy_x_scope_hub_compose.yml` | `x-scope-hub` |

Before running the workflow, configure:

- GitHub Secrets:
  - `GHCR_USERNAME`
  - `GHCR_TOKEN`
  - `CLOUDFLARE_DNS_API_TOKEN`
  - `WORKSPACE_REPO_TOKEN`
  - `ACCOUNTS_ANSIBLE_VARS_YAML`
  - `RAG_SERVER_ANSIBLE_VARS_YAML`
  - `X_CLOUD_FLOW_ANSIBLE_VARS_YAML`
  - `X_OPS_AGENT_ANSIBLE_VARS_YAML`
  - `X_SCOPE_HUB_ANSIBLE_VARS_YAML`
  - `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`
- GitHub Variables:
  - `SINGLE_NODE_VPS_SSH_HOST`
  - `SINGLE_NODE_VPS_SSH_USER`
  - `SINGLE_NODE_VPS_SSH_PORT`
  - `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS`

Manual run in GitHub UI:

1. Open `Actions`
2. Select `Single-Node Service Release`
3. Click `Run workflow`
4. Fill:
   - `service`: one of `accounts`, `accounts-preview`, `rag-server`, `x-cloud-flow`, `x-ops-agent`, `x-scope-hub`
   - `service_ref`: branch, tag, or commit SHA from the service repository
   - `run_apply`: `false` for dry-run only, `true` to continue through the final apply stage

Manual run with GitHub CLI:

```bash
gh workflow run single_node_service_release.yml \
  -R cloud-neutral-toolkit/github-org-cloud-neutral-toolkit \
  -f service=rag-server \
  -f service_ref=main \
  -f run_apply=false
```

Workflow stages:

1. Build and push the image to `ghcr.io`
2. Update the release DNS record
3. Run `ansible-playbook -D -C`
4. Optionally run `ansible-playbook -D`

## StackFlow GitHub Actions Secrets

This repo includes `.github/workflows/stackflow.yaml` which plans/validates StackFlow configs stored in the `cloud-neutral-toolkit/gitops` repo (e.g. `gitops/StackFlow/svc-plus.yaml`).

Secrets (by phase):
- Plan/Validate (today):
  - `GITOPS_CHECKOUT_TOKEN` (optional): needed only if `cloud-neutral-toolkit/gitops` is private or default `GITHUB_TOKEN` cannot read it.
- Future phases (not enabled in this workflow yet):
  - `CLOUDFLARE_API_TOKEN`: dns-apply (cloudflare).
  - `ALIYUN_AK`, `ALIYUN_SK`: dns-apply (alicloud).
  - `GCP_*`: iac/deploy; prefer Workload Identity Federation (OIDC) and avoid long-lived JSON keys.
  - `VERCEL_TOKEN`: optional vercel-side validation/config via API.

### How To Create `GITOPS_CHECKOUT_TOKEN` (Fine-grained PAT)

Use a fine-grained PAT with least privilege, scoped to only the `cloud-neutral-toolkit/gitops` repository.

Steps:
1. GitHub: `Settings` -> `Developer settings` -> `Personal access tokens` -> `Fine-grained tokens`
2. Click `Generate new token`
3. `Resource owner`: select `cloud-neutral-toolkit`
4. `Repository access`: select `Only select repositories`, then choose only `cloud-neutral-toolkit/gitops`
5. `Permissions`:
   - `Repository permissions` -> `Contents: Read`
   - Keep everything else as `No access`
6. Generate token and copy it
7. In `cloud-neutral-toolkit/github-org-cloud-neutral-toolkit`:
   - `Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`
   - Name: `GITOPS_CHECKOUT_TOKEN`
   - Value: the token
8. Verify:
   - Run GitHub Actions workflow `StackFlow (GitOps Plan/Validate)`
   - If you no longer see `repository not found` / `permission denied`, the token is working

### Alternative: GitHub App (Long-Term)

For long-term governance, use a GitHub App installed on the org with:
- Repository: only `cloud-neutral-toolkit/gitops`
- Permission: `Contents: Read`

Then update the workflow to use the App installation token for checkout.
