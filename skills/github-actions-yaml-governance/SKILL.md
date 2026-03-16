# Skill: github-actions-yaml-governance

## Purpose

Keep GitHub Actions workflow YAML small, readable, and orchestration-only.

## Core Rule

Workflow YAML should describe:

- triggers
- permissions
- concurrency
- job graph
- action wiring
- script entrypoints

Workflow YAML should not embed operational logic.

## Required Rules

1. No multi-line business logic in workflow `run` blocks.
2. No embedded Python programs inside workflow YAML.
3. No embedded shell decision trees inside workflow YAML.
4. Repeated logic must move to `scripts/github-actions/`.
5. Generated runtime config must come from checked-in templates.
6. Secrets must come from GitHub Secrets or runtime env only.
7. Workflow files must stay readable top-to-bottom in one pass.

## Preferred Structure

- `.github/workflows/*.yml`
  - orchestration only
- `scripts/github-actions/*.sh`
  - shell entrypoints for workflow steps
- `scripts/github-actions/*.py`
  - parsing/rendering helpers when shell is not a good fit
- `ansible/*.tmpl`
  - checked-in runtime templates

## Review Checklist

- Can a reviewer understand the workflow without reading 100 lines of inline shell?
- Does each `run:` step call a named script instead of containing custom logic?
- Are inventory/env/config files rendered from checked-in templates instead of heredocs in YAML?
- Are secrets referenced only via `${{ secrets.* }}` and never hardcoded?
- Does the workflow still pass YAML parsing after refactor?
- Do all new helper scripts have local syntax validation commands?

## Minimum Verification

- `python3 - <<'PY' ... yaml.safe_load(...)`
- `bash -n scripts/github-actions/*.sh`
- `python3 -m py_compile scripts/github-actions/*.py`
- `git diff --check`
