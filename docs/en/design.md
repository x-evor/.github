# Design

This repository is the control plane for cross-repository governance, architecture baselines, release policies, and execution checklists.

Use this page to consolidate design decisions, ADR-style tradeoffs, and roadmap-sensitive implementation notes.

## Current code-aligned notes

- Documentation target: `github-org-cloud-neutral-toolkit`
- Repo kind: `control`
- Manifest and build evidence: repository structure and scripts only
- Primary implementation and ops directories: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- Package scripts snapshot: No package.json scripts were detected.

## Existing docs to reconcile

- `architecture/rbac-plan-quota-architecture.md`
- `design-development/service-chain-auth-implementation.md`
- `feature-flows/accounts-oauth-binding-spec.md`
- `feature-flows/accounts-plan-quota-policy-spec.md`
- `feature-flows/ai-platform-gateway-rag-mcp-ops-agent.md`
- `feature-flows/console-oauth-integration-spec.md`
- `feature-flows/vless-qr-code-flow.md`
- `features/accounts-oauth-binding-spec.md`

## What this page should cover next

- Describe the current implementation rather than an aspirational future-only design.
- Keep terminology aligned with the repository root README, manifests, and actual directories.
- Link deeper runbooks, specs, or subsystem notes from the legacy docs listed above.
- Promote one-off implementation notes into reusable design records when behavior, APIs, or deployment contracts change.
