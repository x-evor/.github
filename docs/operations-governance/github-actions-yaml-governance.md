# GitHub Actions YAML Governance

## Objective

Keep GitHub Actions workflow files readable, reviewable, and low-risk.

In this repository, workflow YAML is the control plane. It should remain orchestration-only.

## Rule

Workflow YAML must not become the place where release logic lives.

Use workflow YAML for:

- triggers
- inputs
- permissions
- concurrency
- job dependencies
- action selection
- external script invocation

Move implementation logic out of workflow YAML into checked-in scripts and templates.

## Mandatory Constraints

1. Do not embed multi-line operational shell logic in workflow YAML.
2. Do not embed Python programs in workflow YAML.
3. Do not build large JSON/YAML payloads inline unless they are trivial one-liners.
4. Do not render runtime inventory or config through long heredocs in workflow YAML.
5. Put reusable runtime logic in `scripts/github-actions/`.
6. Put reusable rendered files in checked-in templates such as `ansible/*.tmpl`.
7. Keep secrets in GitHub Secrets; keep non-sensitive defaults in checked-in catalogs and templates.

## Repository Layout Convention

- `.github/workflows/*.yml`
  - orchestration only
- `scripts/github-actions/*.sh`
  - workflow entrypoint scripts
- `scripts/github-actions/*.py`
  - render/parse/normalize helpers
- `ansible/*.tmpl`
  - runtime-rendered inventory or config templates
- `config/single-node-release/**/*.yaml`
  - checked-in release metadata and defaults

## Review Standard

A workflow change should satisfy all of the following:

- a human can read the workflow file end-to-end without parsing embedded programs
- each non-trivial `run:` step delegates to a named script
- repeated step logic is not duplicated across stages
- inventory/env rendering is template-based
- secret handling is separated from checked-in public config

## Verification Standard

At minimum, validate:

```bash
python3 - <<'PY'
import yaml, pathlib
yaml.safe_load(pathlib.Path('.github/workflows/service_release_control_plane.yml').read_text())
print('workflow yaml ok')
PY

for f in scripts/github-actions/*.sh; do
  bash -n "$f"
done

python3 -m py_compile scripts/github-actions/*.py
git diff --check
```

## Current Example

`Service Release Control Plane` should follow this pattern:

- workflow YAML wires stages together
- scripts under `scripts/github-actions/` perform the step logic
- `ansible/inventory.ini.tmpl` renders the runtime inventory

This is the preferred baseline for future workflow changes in this control repo.
