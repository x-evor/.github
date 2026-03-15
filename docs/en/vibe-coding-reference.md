# Vibe Coding Reference

This repository is the control plane for cross-repository governance, architecture baselines, release policies, and execution checklists.

Use this page to align AI-assisted coding prompts, repo boundaries, safe edit rules, and documentation update expectations.

## Current code-aligned notes

- Documentation target: `github-org-cloud-neutral-toolkit`
- Repo kind: `control`
- Manifest and build evidence: repository structure and scripts only
- Primary implementation and ops directories: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- Package scripts snapshot: No package.json scripts were detected.

## Existing docs to reconcile

- `Runbook/Fix-Agent-404-And-UUID-Change.md`
- `Runbook/Setup-Sandbox-Mode-and-Agent-Sync.md`
- `feature-flows/ai-platform-gateway-rag-mcp-ops-agent.md`
- `plans/multi-agent-support-implementation-task-checklist.md`

## What this page should cover next

- Describe the current implementation rather than an aspirational future-only design.
- Keep terminology aligned with the repository root README, manifests, and actual directories.
- Link deeper runbooks, specs, or subsystem notes from the legacy docs listed above.
- Review prompt templates and repo rules whenever the project adds new subsystems, protected areas, or mandatory verification steps.
