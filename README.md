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
