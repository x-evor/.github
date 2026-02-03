# Multi-Repo Governance Standard

## 1) Branching Convention

- Feature: `codex/feat/<topic>`
- Fix: `codex/fix/<topic>`
- Chore: `codex/chore/<topic>`
- Release prep: `codex/release/<topic>`

## 2) Commit Convention

Use Conventional Commits:

- `feat(scope): ...`
- `fix(scope): ...`
- `refactor(scope): ...`
- `chore(scope): ...`
- `docs(scope): ...`

Examples:

- `feat(auth): support internal service token rotation`
- `fix(console): keep API proxy auth header on retry`

## 3) Pull Request Standard

Every PR must include:

- Objective and impacted repos
- Files changed summary
- Risk assessment
- Test commands and results
- Rollback notes

Use the default template in `.github/pull_request_template.md`.

## 4) Version Strategy

- SemVer for each repo: `MAJOR.MINOR.PATCH`
- Bump rules:
  - MAJOR: breaking API/protocol/auth contract changes
  - MINOR: backward-compatible features
  - PATCH: backward-compatible bug fixes
- Release tag format: `<repo>-vX.Y.Z`

## 5) Release Flow

1. Freeze impacted repos for release scope.
2. Verify CI and dependency compatibility.
3. Release in dependency order (see `docs/operations-governance/release-checklist.md`).
4. Run smoke/integration checks across impacted service chain.
5. Announce release + known limitations + rollback entrypoint.

## 6) Environment Variable and Secret Rule

- Local development must use `.env` (gitignored).
- Team baseline template must be `.env.example` (keys only, no values).
- Production/staging must use Secret Manager or platform environment variables.
- Never commit real secrets/tokens/passwords/private keys to Git.
- Any PR that adds a new env var must update `.env.example` and release checklist notes.

## 7) Inheritance Rule

- This governance file is global default.
- Repo-local docs can extend it but must not conflict on safety gates.
