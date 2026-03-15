# Release Branch Policy (release/*)

This doc defines how Cloud-Neutral Toolkit repositories handle production releases.

## Goals

- `main` is the preview branch (fast iteration).
- `release/*` are production release lines.
- `release/*` changes are "cherry-pick only" (process), and protected (enforceable).
- Tag association across repos is done via a committed release manifest.

## Branch Model

- `main`: preview
  - normal PR flow, merges normally
  - can be ahead of production
- `release/<version>`: production
  - created as needed (example: `release/v0.1`)
  - only release managers update it
  - changes come from cherry-picking commits already merged into `main`

## Ruleset / Protection Requirements (release/*)

At minimum, enforce:

- block deletion
- block non-fast-forward (no force-push)
- require linear history

Important: you cannot simultaneously forbid PR merges and forbid all pushes; that would make the branch immutable.
The intended policy is:

- enforce no force-push + linear history + no deletion
- restrict updates to release managers (GitHub ruleset "bypass actors" / branch protection "restrict who can push")
- treat "cherry-pick only" as a process rule

## Tooling

Use the skill in this repo:

- Skill: `skills/release-branch-policy/SKILL.md`
- Apply ruleset: `skills/release-branch-policy/scripts/apply_ruleset.sh`
- Generate release manifest: `skills/release-branch-policy/scripts/generate_release_manifest.sh`

## Release Manifest (Cross-Repo Tag Association)

Tags are per-repo. To represent a coordinated release, commit a manifest file in the control repo.

Recommended layout:

- `releases/v0.1.yaml`

Generate (read-only, local):

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit
./skills/release-branch-policy/scripts/generate_release_manifest.sh v0.1
```

## Cherry-Pick Workflow (Release Managers)

1. Merge change into `main`.
2. Identify commits to include.
3. In the target repo, checkout `release/<version>` (create if needed).
4. Cherry-pick commits.
5. Push `release/<version>` (only release managers should have update permission).
6. Optionally tag `v0.1` at the release tip (per repo).
7. Update and commit the manifest in the control repo.

