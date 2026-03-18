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
- Git history remediation skill: [`skills/git-history-secret-remediation/SKILL.md`](skills/git-history-secret-remediation/SKILL.md)
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
- Shared ClawHub-style skill sources live under `skills/`.
- Build a distributable `.skill` package with `python3 scripts/skills/package_skill.py skills/<skill-name> dist/skills`.
- Distribute a skill to child repos with `python3 scripts/skills/distribute_skill.py skills/<skill-name> /path/to/repo [...]`.

## Release Control Plane

This repo coordinates the Cloud Run-like release control plane for the `svc.plus` services.

Current runtime profile:

- `single-node-docker-compose`

Planned runtime profiles:

- `single-node-k3s`
- `cluster-k8s`

Reference docs:

- Ansible overview: [`ansible/README.md`](ansible/README.md)
- Design v1: [`docs/plans/2026-03-16-single-node-cloud-run-like-release-design.md`](docs/plans/2026-03-16-single-node-cloud-run-like-release-design.md)
- Workflow details: [`docs/operations-governance/service-release-control-plane-workflow.md`](docs/operations-governance/service-release-control-plane-workflow.md)
- Local OrbStack workflow: [`docs/operations-governance/orbstack-local-build-and-tar-deploy.md`](docs/operations-governance/orbstack-local-build-and-tar-deploy.md)
- Repo catalog: [`config/single-node-release/repositories.json`](config/single-node-release/repositories.json)
- Service catalog: [`config/single-node-release/services/`](config/single-node-release/services)
  - Common service config: `config/single-node-release/services/common.yaml`
  - Track/service overrides: `config/single-node-release/services/<track>-<service>.yaml`

Control-plane boundary:

- This repo owns catalog, workflow orchestration, release policy, and DNS/update flow.
- Each sub repo still owns its own Dockerfile, playbook, runtime env shape, and service-specific startup behavior.

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

### Local OrbStack Build and Tar Deploy

For macOS local development and release preparation, prefer OrbStack as the Docker runtime.

Build locally, export a tar, then ship and load it on the VPS:

```bash
scripts/single-node/build_local_image_tar.sh \
  --context /Users/shenlan/workspaces/cloud-neutral-toolkit/<service-repo> \
  --image local/<service-name> \
  --tag "$(git -C /Users/shenlan/workspaces/cloud-neutral-toolkit/<service-repo> rev-parse --short HEAD)" \
  --tar /tmp/<service-name>.tar \
  --platform linux/amd64

scripts/single-node/ship_image_tar.sh \
  --host root@us-xhttp.svc.plus \
  --tar /tmp/<service-name>.tar \
  --remote-dir /opt/cloud-neutral/<service-name>/<release-name>
```

The full workflow and examples are documented in:

- [`docs/operations-governance/orbstack-local-build-and-tar-deploy.md`](docs/operations-governance/orbstack-local-build-and-tar-deploy.md)

### GitHub Actions Manual Release

Workflow file:

- `.github/workflows/service_release_apiserver-deploy.yml`

Core release-enabled services:

| Service | Repo | Repo Category | Playbook | Prod Stable Domain | Preview Stable Domain |
| --- | --- | --- | --- | --- | --- |
| accounts | `accounts.svc.plus` | `api` | `ansible/playbooks/deploy_accounts_compose.yml` | `accounts.svc.plus` | `accounts-preview.svc.plus` |
| rag-server | `rag-server.svc.plus` | `api` | `ansible/playbooks/deploy_rag_server_compose.yml` | `rag-server.svc.plus` | `rag-server-preview.svc.plus` |
| x-cloud-flow | `x-cloud-flow.svc.plus` | `api` | `ansible/playbooks/deploy_x_cloud_flow_compose.yml` | `x-cloud-flow.svc.plus` | `x-cloud-flow-preview.svc.plus` |
| x-ops-agent | `x-ops-agent.svc.plus` | `api` | `ansible/playbooks/deploy_x_ops_agent_compose.yml` | `x-ops-agent.svc.plus` | `x-ops-agent-preview.svc.plus` |
| x-scope-hub | `x-scope-hub.svc.plus` | `api` | `ansible/playbooks/deploy_x_scope_hub_compose.yml` | `x-scope-hub.svc.plus` | `x-scope-hub-preview.svc.plus` |

Workflow input model:

- `service`: logical service key from `config/single-node-release/services/common.yaml`
- `track`: `prod` or `preview`
- `service_ref`: branch, tag, or commit SHA in the service repo
- `run_apply`: `false` for dry-run only, `true` for final apply

For `git-submodule` services such as `accounts.svc.plus`, the effective source revision is the submodule pointer currently committed in this control repo. `service_ref` only applies to `remote-checkout` services.

Release behavior:

- CI builds and pushes the image to `ghcr.io`
- CI creates the immutable release DNS record
- CD writes the deploy key to the runner, renders a temporary inventory from `ansible/inventory.ini.tmpl`, and runs the sub-repo playbook against the single VPS
- Stable domains stay fixed and should already point to the deploy host
- Release domains are unique per deployment:
  - prod + `release/*`: `<release-prefix>-<deploy-hostname>-<release-name>-<git-short-commit>.<domain>`
  - preview or non-`release/*`: `<release-prefix>-<deploy-hostname>-<git-short-commit>.<domain>`

Before running the workflow, configure:

- GitHub Secrets:
  - `GHCR_TOKEN`
  - `CLOUDFLARE_DNS_API_TOKEN`
  - `WORKSPACE_REPO_TOKEN`
  - `INTERNAL_SERVICE_TOKEN`
  - `ACCOUNTS_DB_PASSWORD`
  - `ACCOUNTS_SMTP_PASSWORD`
  - `RAG_SERVER_ANSIBLE_VARS_YAML`
  - `X_CLOUD_FLOW_ANSIBLE_VARS_YAML`
  - `X_OPS_AGENT_ANSIBLE_VARS_YAML`
  - `X_SCOPE_HUB_ANSIBLE_VARS_YAML`
  - `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`

`GHCR_USERNAME` is defined directly in the workflow env and currently set to `svc-design`. Update it only when the owner of `GHCR_TOKEN` changes.

Default SSH connection values are also defined directly in the workflow env:

- `SINGLE_NODE_VPS_SSH_HOST=5.78.45.49`
- `SINGLE_NODE_VPS_SSH_USER=root`
- `SINGLE_NODE_VPS_SSH_PORT=22`
- `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS=` (empty by default; the runner can `ssh-keyscan`)

The SSH private key preparation standard is documented here:

- [pre-github-deploy-key.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/operations-governance/pre-github-deploy-key.md)

For manual `workflow_dispatch` runs, these values can be overridden with optional inputs:

- `ssh_host`
- `ssh_user`
- `ssh_port`
- `ssh_known_hosts`

For `accounts.svc.plus`, non-sensitive release defaults live in the checked-in file `subrepos/accounts.svc.plus/ansible/vars/accounts.release.public.yml`. Only `INTERNAL_SERVICE_TOKEN`, `ACCOUNTS_DB_PASSWORD`, and `ACCOUNTS_SMTP_PASSWORD` need to be synced from the local control-repo `.env` into GitHub Organization Secrets.

Manual run in GitHub UI:

1. Open `Actions`
2. Select `Service Release Control Plane`
3. Click `Run workflow`
4. Fill:
   - `service`: one of `accounts`, `rag-server`, `x-cloud-flow`, `x-ops-agent`, `x-scope-hub`
   - `track`: `prod` or `preview`
   - `service_ref`: branch, tag, or commit SHA from the service repository
   - `run_apply`: `false` for dry-run only, `true` to continue through the final apply stage
   - optional `ssh_host`, `ssh_user`, `ssh_port`, `ssh_known_hosts`: override the built-in SSH target defaults for this run only

For `accounts.svc.plus`, update and push the control-repo submodule pointer first, then run the workflow. The `service_ref` input is ignored for that `git-submodule` source.

Manual run with GitHub CLI:

```bash
gh workflow run service_release_apiserver-deploy.yml \
  -R cloud-neutral-toolkit/github-org-cloud-neutral-toolkit \
  -f service=accounts \
  -f track=prod \
  -f service_ref=release/2026-03-16 \
  -f ssh_host=5.78.45.49 \
  -f ssh_user=root \
  -f ssh_port=22 \
  -f run_apply=false
```

Workflow stages:

1. Build and push the image to `ghcr.io`
2. Update the immutable release DNS record
3. Run the sub-repo `ansible-playbook -D -C`
4. Optionally run the sub-repo `ansible-playbook -D`

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
