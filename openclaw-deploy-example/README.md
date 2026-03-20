# OpenClaw Deploy Example In Control Repo

This directory vendors the contents of the standalone
`openclaw-deploy-example` project into the control repo as a nested example
workspace.

## Purpose

Use this directory as a reference bundle for:

- OpenClaw local deployment examples
- APISIX / Caddy / Kong / Vault integration examples
- GCP Cloud Run deployment examples
- gateway config, runbooks, and related scripts

The control repo keeps it under a subdirectory so it does not overwrite the
control-plane root structure.

## Layout

- `config/`: example runtime profiles
- `deploy/`: deployment manifests and helper scripts
- `docs/`: bilingual architecture, deployment, and runbook docs
- `patchs/`: patch examples
- `scripts/`: local helper scripts
- `svc-ai-gateway/`: gateway compose/config example

## Usage In This Repo

Typical entrypoints:

- `openclaw-deploy-example/docs/README.md`
- `openclaw-deploy-example/deploy/gcp/cloud-run/README.md`
- `openclaw-deploy-example/deploy/apisix/README.md`

Run scripts from inside this directory when they assume local relative paths.
For example:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/openclaw-deploy-example
```

## Safety Notes

- Source `.git/` metadata was intentionally not imported.
- Source root `.env` was intentionally not imported.
- Review any nested `.env.example` or `.env.local.example` files before use.
