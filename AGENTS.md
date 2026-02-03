# AGENTS.md (Unified Multi-Repo Rules)

This repository is the control plane for the Cloud-Neutral Toolkit multi-repo project.

## 1) Scope

- Use this repo to define standards, plans, and cross-repo execution checklists.
- Keep repo-specific implementation details inside each sub-repo.
- Treat this file as the default policy all related repos should inherit.

## 2) Codex Work Rules

- Default workspace: `console.svc.plus.code-workspace`.
- Handle one cross-repo objective per task.
- Do not mix unrelated refactors with release-critical changes.
- Prefer small, reversible changes and explicit verification commands.

## 3) Required Output Format (for cross-repo tasks)

When asked to implement or design cross-repo changes, always output:

1. **Change Scope**: impacted repos + objective
2. **Files Changed**: exact paths grouped by repo
3. **Risk Points**: compatibility/security/runtime risks
4. **Test Commands**: copy-paste commands by repo
5. **Rollback Plan**: revert order and any config rollback

## 4) Unified Standards (inherited by all repos)

- Branch naming: `codex/<type>/<short-topic>`
  - Example: `codex/feat/internal-service-token`
- Commit style: Conventional Commits
  - Example: `feat(auth): add internal token verification`
- PR title style: same as first commit style
- PR body must include: Scope, Risk, Tests, Rollback
- Versioning: SemVer (`MAJOR.MINOR.PATCH`)
- Release tags: `<repo-name>-vX.Y.Z`

## 5) Change Safety Gates

Before merge/release, check:

- Dependency version compatibility (especially shared SDK/client)
- Required environment variables in each impacted repo
- CI status green for all impacted repos
- API contract compatibility (request/response/auth headers)

## 6) Source of Truth

- `docs/architecture/project-overview.md`: architecture and ownership
- `docs/operations-governance/governance.md`: branch/PR/commit/version/release policy
- `docs/operations-governance/release-checklist.md`: publish order and release gate checks
- `docs/operations-governance/cross-repo-tasks.md`: active backlog + execution templates
- `skills/env-secrets-governance/SKILL.md`: env/secrets handling standard

## 7) Skill Rule for Env/Secret Changes

- Any task involving env vars, tokens, passwords, or keys must follow `skills/env-secrets-governance/SKILL.md`.
