# Ollama Cheap-Model Execution Rule

This rule defines what low-cost local models are allowed to do when asked to execute migration-related test tasks.

## Scope

Applies to:

- Docker Compose migration smoke tests
- preview/stable route verification
- low-risk config inspection
- resource-fit checks

Does not apply to:

- destructive infra changes
- secret rotation
- production cutover
- schema changes

## Allowed Actions

Cheap models may:

1. Read runbooks, compose files, and example env files.
2. Run non-destructive verification commands.
3. Render or validate static configs.
4. Report risks and missing prerequisites.

## Disallowed Actions

Cheap models must not:

1. Print secret values from `.env`, environment variables, or generated manifests.
2. Execute destructive commands such as `rm`, `docker compose down -v`, or rollback traffic without explicit approval.
3. Invent architecture changes outside the documented migration path.
4. Expand the scope from `accounts + rag-server + APISIX + shared stunnel-client` unless explicitly asked.

## Required Behavior

1. Default to verification first.
2. Prefer dry-run style commands.
3. If a command may mutate the runtime, say so explicitly.
4. Keep outputs short and checklist-shaped.
5. On uncertainty, stop and report the missing input.

## Default Command Set

Preferred commands for cheap-model execution:

```bash
python3 scripts/docker-compose-lite/estimate_capacity.py
bash scripts/docker-compose-lite/verify_stack.sh
docker compose -f deploy/docker-compose-lite/docker-compose.yaml config
docker compose -f deploy/docker-compose-lite/docker-compose.yaml ps
```

## Secret Handling

Follow `skills/env-secrets-governance/SKILL.md`.

Rules:

- only reference secret key names
- never echo secret values
- never write real secrets into repo files

## Recommended Prompt Pattern

Use prompts shaped like:

```text
Use the docker-compose-lite-migration skill.
Verify the lightweight migration stack only.
Do not modify secrets.
Report stack status, resource fit, route status, risks, and next action.
```
