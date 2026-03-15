# Developer Guide

This repository is the control plane for cross-repository governance, architecture baselines, release policies, and execution checklists.

Use this page to document local setup, project structure, test surfaces, and contribution conventions tied to the current codebase.

## Current code-aligned notes

- Documentation target: `github-org-cloud-neutral-toolkit`
- Repo kind: `control`
- Manifest and build evidence: repository structure and scripts only
- Primary implementation and ops directories: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- Package scripts snapshot: No package.json scripts were detected.

## Existing docs to reconcile

- `design-development/service-chain-auth-implementation.md`
- `testing/full-stack-test-plan.md`

## What this page should cover next

- Describe the current implementation rather than an aspirational future-only design.
- Keep terminology aligned with the repository root README, manifests, and actual directories.
- Link deeper runbooks, specs, or subsystem notes from the legacy docs listed above.
- Keep setup and test commands tied to actual package scripts, Make targets, or language toolchains in this repository.
