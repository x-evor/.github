---
name: unified-setup-sh
description: Standardize a single scripts/setup.sh across Cloud-Neutral Toolkit repos (curl | bash), with safe cloning, dependency install, and next-step printing. Use when adding or updating setup.sh in any repo.
---

# Unified Setup Script Skill

## Goal

Provide one consistent `scripts/setup.sh` pattern that can be copied into any repo so users can run:

```bash
curl -fsSL "https://raw.githubusercontent.com/cloud-neutral-toolkit/<repo>/main/scripts/setup.sh?$(date +%s)" | bash -s -- <repo>
```

## Safety Rules

- Never write secrets. If needed, create `.env` from `.env.example` only.
- Never run destructive operations (no `rm -rf`, no system package installs).
- If prerequisites are missing (node/yarn/go/docker), print clear instructions and exit non-zero.
- Script must be idempotent: if repo dir exists, do not switch branches or overwrite config.

## What To Produce In A Target Repo

1. Add `scripts/setup.sh` using the template: `assets/setup.sh`.
2. Make it executable (`chmod +x scripts/setup.sh`).
3. Update root `README.md` with a copy/paste snippet for curl-based install.

## Supported Repo Types (Detection Heuristics)

The template supports (auto-detected):
- Node/Yarn: `package.json` (uses `corepack enable` if present, runs `yarn install`)
- Go: `go.mod` (runs `go mod download`)

Optional hooks (if present, run after deps):
- `scripts/post-setup.sh`

## Template

Copy `skills/unified-setup-sh/assets/setup.sh` into `<target-repo>/scripts/setup.sh`.

If you need repo-specific parameters, add them behind `--` and document in README:

```bash
curl -fsSL ".../setup.sh?$(date +%s)" | bash -s -- <repo> -- --ref main --dir <dir>
```

## Secrets Documentation Convention

If the setup flow requires secrets later (deploy/apply), only document secret names in README and reference `skills/env-secrets-governance/SKILL.md`.

