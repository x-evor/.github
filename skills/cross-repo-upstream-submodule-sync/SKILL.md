---
name: cross-repo-upstream-sync
description: Use when a change must be made in an upstream repo that is mirrored into this control repo as a sibling checkout. Covers the required sequence: fix and push the upstream repo first, then verify the control repo references the pushed upstream commit, then commit and push the control-plane metadata change.
version: 1.0.0
author: Cloud Neutral Toolkit
tags: [git, cross-repo, release, sync, control-repo]
---

# Cross-Repo Upstream Sync

## Goal

Use this skill when the real source repo lives outside the control repo and the control repo tracks it through a sibling checkout.

Default example:

- upstream repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus`
- sibling checkout: `/Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus`
- control repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit`

## Required Order

Always execute in this order:

1. fix the upstream repo
2. commit and push the upstream repo
3. verify the control-plane reference in the control repo
4. commit and push the control repo pointer change

Do not make the primary code change only inside the control repo metadata checkout. The sibling repo is the source of truth.

## Preconditions

Before editing:

- confirm the upstream repo path
- confirm the sibling checkout path
- confirm the target branch for the upstream repo
- confirm the control repo branch
- inspect `git status --short` in all three working trees

If the task involves env vars, tokens, passwords, keys, or secret files, also follow [../env-secrets-governance/SKILL.md](../env-secrets-governance/SKILL.md).

## Execution Workflow

### 1) Fix the upstream repo

Work in the standalone upstream repo first.

Example:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus
git checkout main
git pull --ff-only origin main
```

Make the code change there, not in the control repo metadata checkout.

Run the narrowest relevant validation first, then the broader package-level validation if needed.

### 2) Commit and push the upstream repo

Use Conventional Commits.

Example:

```bash
git add <files>
git commit -m "fix(accounts): ensure tenant schema exists before bootstrap"
git push origin main
```

Record the pushed commit SHA because the control repo will need to reference it.

### 3) Verify the control-plane reference

Move to the sibling repo path and confirm it is on the pushed upstream branch tip.

Example:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus
git fetch origin --prune
git checkout main
git pull --ff-only origin main
```

Verify the sibling checkout now points at the intended upstream commit:

```bash
git rev-parse HEAD
```

### 4) Commit and push the control repo

Commit only the control-plane metadata change in the control repo unless the task explicitly also updates docs or governance files there.

Example:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit
git add config/single-node-release/repositories.json
git commit -m "chore(release): update accounts.svc.plus reference"
git push origin main
```

## Verification

Run these checks before closing the task:

### Upstream repo

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus
git status --short
git rev-parse HEAD
git log --oneline -1
```

### Sibling checkout

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus
git status --short
git rev-parse HEAD
```

### Control repo

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit
git status --short
git diff --stat
git log --oneline -1
```

## Output Contract

When reporting completion for a cross-repo sync, include:

1. Change Scope
2. Files Changed
3. Risk Points
4. Test Commands
5. Rollback Plan

This matches the control repo policy in `AGENTS.md`.

## Failure Handling

If upstream push fails:

- do not advance the sibling checkout
- report the upstream commit SHA and the push failure reason

If the sibling checkout has local edits:

- stop and inspect them
- do not overwrite or reset user changes without explicit approval

If the control repo push fails:

- leave the control repo commit in place locally
- report the local commit SHA and the exact remote failure

## Notes

- Prefer `git pull --ff-only` and other non-interactive git commands.
- Keep the upstream repo and sibling checkout on the same target branch unless the release process explicitly requires otherwise.
- If the upstream repo is on a release branch but the user explicitly asks to push `main`, obey the explicit instruction and say so in the status update.
