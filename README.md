# Cloud-Neutral Toolkit Control Repo

This repository is the management hub for a multi-repo project under the `cloud-neutral-toolkit` org.

## Quick Start

- Open the workspace: `console.svc.plus.code-workspace`
- Read architecture and ownership: `docs/架构/project-overview.md`
- Follow unified rules: `AGENTS.md` and `docs/运维治理/governance.md`
- Run release flow from checklist: `docs/运维治理/release-checklist.md`
- Track cross-repo work: `docs/运维治理/cross-repo-tasks.md`

## Control Documents

- Project overview: [`docs/架构/project-overview.md`](docs/架构/project-overview.md)
- Agent operating rules: [`AGENTS.md`](AGENTS.md)
- Governance standard: [`docs/运维治理/governance.md`](docs/运维治理/governance.md)
- Release checklist: [`docs/运维治理/release-checklist.md`](docs/运维治理/release-checklist.md)
- Cross-repo task board: [`docs/运维治理/cross-repo-tasks.md`](docs/运维治理/cross-repo-tasks.md)
- Docs index: [`docs/README.md`](docs/README.md)
- Workspace file: [`console.svc.plus.code-workspace`](console.svc.plus.code-workspace)
- Env template: [`.env.example`](.env.example)
- Env/secret skill: [`skills/env-secrets-governance/SKILL.md`](skills/env-secrets-governance/SKILL.md)

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
