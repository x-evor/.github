---
name: docker-compose-lite-migration
description: Execute and verify the lightweight single-VPS migration path for accounts + rag-server + APISIX standalone + shared stunnel-client. Use for cheap-model test runs, preview verification, and Docker Compose smoke checks.
version: 1.0.0
author: Cloud Neutral Toolkit
tags: [migration, docker-compose, apisix, stunnel, accounts, rag-server, ollama]
---

# Docker Compose Lite Migration Skill

## Goal

Provide a stable, low-context workflow for cheap models to validate the lightweight migration path:

- `accounts.svc.plus`
- `rag-server.svc.plus`
- `APISIX` standalone
- shared `stunnel-client`

This skill is intentionally scoped to **single-VPS smoke tests and migration verification**, not architecture redesign.

## When To Use

Use this skill when the task is:

- verify the Docker Compose migration stack
- render or inspect `deploy/docker-compose-lite`
- run lightweight health checks
- confirm stable / preview route wiring
- check whether the stack still fits a `2C2G` or `2C4G` VPS

Do not use this skill for:

- K3s migration execution
- multi-node orchestration
- large-scale production rollout planning
- secrets refactoring beyond documented names

## Source Of Truth

- `docs/Runbook/Migrate-CloudRun-Core-To-DockerCompose-2C2G.md`
- `deploy/docker-compose-lite/docker-compose.yaml`
- `deploy/docker-compose-lite/apisix/apisix.yaml`
- `deploy/docker-compose-lite/stunnel/stunnel.conf`
- `scripts/docker-compose-lite/estimate_capacity.py`
- `scripts/docker-compose-lite/verify_stack.sh`
- `skills/env-secrets-governance/SKILL.md`

## Execution Rules

1. Prefer **verification tasks** over edits.
2. Do not print secret values from `.env` or runtime env.
3. If a task involves provider keys, only mention key names, never values.
4. Prefer:
   - `python3 scripts/docker-compose-lite/estimate_capacity.py`
   - `bash scripts/docker-compose-lite/verify_stack.sh`
   - `docker compose config`
   - `docker compose ps`
5. If editing is required, keep changes inside:
   - `docs/Runbook/`
   - `deploy/docker-compose-lite/`
   - `scripts/docker-compose-lite/`
6. Treat `stunnel-client` as a **shared singleton**. Never add per-service stunnel sidecars in this flow.

## Expected Output Shape

When reporting results, keep the output compact and structured:

1. Stack status
2. Resource fit
3. Route / TLS status
4. Risks
5. Next action

## Smoke Checklist

- `docker compose` file parses
- `apisix` service present
- `stunnel-client` service present
- `accounts` service present
- `rag-server` service present
- APISIX admin port configured
- `stunnel.conf` accepts on `15432`
- `accounts` and `rag-server` point to `stunnel-client`
- estimated memory stays within the target VPS budget

## Cheap-Model Guidance

For low-cost Ollama models:

- stay literal
- do not infer hidden infrastructure
- use the runbook and compose files as primary truth
- if something is missing, report the gap instead of inventing new services
