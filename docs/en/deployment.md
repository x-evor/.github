# Deployment

This repository is the control plane for cross-repository governance, architecture baselines, release policies, and execution checklists.

Use this page to standardize deployment prerequisites, supported topologies, operational checks, and rollback notes.

## Current code-aligned notes

- Documentation target: `github-org-cloud-neutral-toolkit`
- Repo kind: `control`
- Manifest and build evidence: repository structure and scripts only
- Primary implementation and ops directories: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- Package scripts snapshot: No package.json scripts were detected.

## Existing docs to reconcile

- `Runbook/Fix-Agent-404-And-UUID-Change.md`
- `Runbook/Fix-CloudRun-Stunnel-Startup-Failure.md`
- `Runbook/Fix-Rotating-UUID-Sync-Archive-2026-02-06.md`
- `Runbook/Migrate-CloudRun-Core-To-DockerCompose-2C2G.md`
- `Runbook/Migrate-CloudRun-Core-To-SingleNode-K3s-2C4G.md`
- `Runbook/README.md`
- `Runbook/Security-Scrubbing-Archive-2026-02-06.md`
- `Runbook/Setup-Sandbox-Mode-and-Agent-Sync.md`

## What this page should cover next

- Describe the current implementation rather than an aspirational future-only design.
- Keep terminology aligned with the repository root README, manifests, and actual directories.
- Link deeper runbooks, specs, or subsystem notes from the legacy docs listed above.
- Verify deployment steps against current scripts, manifests, CI/CD flow, and environment contracts before each release.
