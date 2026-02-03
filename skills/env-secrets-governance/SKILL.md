# Skill: env-secrets-governance

## Purpose

Standardize environment variable handling and prevent secret leaks across all related repos.

## Rules

1. Local development uses `.env` only (gitignored).
2. Repository template uses `.env.example` only (key names, no values).
3. SIT/Prod uses Secret Manager or platform environment variables.
4. Never commit real tokens/passwords/private keys to Git.

## When changing env vars

- Add/remove key names in `.env.example`.
- Update `docs/governance/release-checklist.md` env checks if process changes.
- Mention env impact in PR Scope/Risk/Rollback.

## Review checklist

- No sensitive values in staged changes.
- `.gitignore` still protects `.env` and `.env.*`.
- New keys are documented and validated in release checks.
