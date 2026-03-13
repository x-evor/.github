---
name: orchestration-run-task
description: Use when Codex or another manager needs to hand off a concrete subtask to opencode, ollama, or gemini through scripts/orchestration/run_worker.sh. Defines the worker execution contract, prompt shape, handoff rules, and fallback behavior.
version: 1.1.0
author: Cloud Neutral Toolkit
tags: [orchestration, run-worker, manager, opencode, ollama, gemini, delegation]
---

# Orchestration Run Task

## Goal

Use [scripts/orchestration/run_worker.sh](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/scripts/orchestration/run_worker.sh) as the single worker execution entrypoint.
Use [config/orchestration/roles.yaml](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/config/orchestration/roles.yaml) as the single source of truth for manager and worker roles.
Use [scripts/orchestration/run_manager.sh](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/scripts/orchestration/run_manager.sh) when a manager should load skills plus role metadata without hand-assembling prompts.
Use `--prompt-mode compact` as the default manager mode. Use `--prompt-mode full` only when debugging or when the compact contract is insufficient.
Use `--template review|deploy|dns-audit` to bind compact mode to a fixed output contract.

This skill is the execution layer under [../codex-multi-cli-orchestrator/SKILL.md](../codex-multi-cli-orchestrator/SKILL.md):

- `codex-multi-cli-orchestrator` decides what to delegate
- `orchestration-run-task` turns that decision into a concrete worker command

Use this skill when:

- a manager must dispatch one bounded subtask to one worker
- the worker prompt must stay short and structured
- the worker result must come back to Codex or another manager for acceptance

## Preconditions

Before using this skill, verify:

1. the worker CLI exists locally
2. the needed model credentials are available
3. the task can be bounded to one worker
4. the target role can be resolved from `config/orchestration/roles.yaml`

Read [references/manager-integration.md](references/manager-integration.md) only when you need manager-side integration patterns for `opencode`, `Antigravity`, or another orchestrator.
Use [scripts/orchestration/orchestration_roles.py](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/scripts/orchestration/orchestration_roles.py) to inspect the configured role map.

## Entrypoint

Use exactly one of these commands:

```bash
scripts/orchestration/run_worker.sh --describe opencode
scripts/orchestration/run_worker.sh opencode "<prompt>"
scripts/orchestration/run_worker.sh ollama "<prompt>"
scripts/orchestration/run_worker.sh gemini "<prompt>"
```

Use `codex` only when the orchestrator explicitly falls back to Codex direct execution.

The wrapper already reads model defaults from [scripts/orchestration/openclaw_cli_defaults.py](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/scripts/orchestration/openclaw_cli_defaults.py). Do not duplicate model selection logic inside prompts.
Do not duplicate role assignment logic outside `config/orchestration/roles.yaml`.

## Role Resolution

Resolve role intent before writing prompts:

- `codex_app`: chief engineer and acceptance gate
- `codex_cli`: direct executor for fallback-only work
- `opencode`: optional orchestration manager
- `antigravity`: optional automation manager
- `opencode_cli`: bounded editor worker
- `gemini_cli`: independent auditor worker
- `ollama`: cheap reviewer worker

Inspect the current role map with:

```bash
python3 scripts/orchestration/orchestration_roles.py
python3 scripts/orchestration/orchestration_roles.py codex_app
python3 scripts/orchestration/orchestration_roles.py --format json
scripts/orchestration/run_worker.sh --describe ollama
```

## Worker Selection

Use `opencode` for:

- bounded repo-aware edits
- playbook, workflow, and docs fixes
- low-risk implementation within explicit path boundaries

Use `ollama` for:

- read-only review
- cheap repeated checks
- config audits
- smoke-check prompt execution

Use `gemini` for:

- read-only cross-check
- short audit
- alternate diagnosis

## Prompt Contract

Every worker prompt must include four fields:

1. `Task`
2. `Allowed`
3. `Forbidden`
4. `Return only`

Keep prompts as short as possible while preserving those fields.

Default read-only prompt:

```text
Task:
- one concrete objective

Allowed:
- explicit read-only scope

Forbidden:
- secrets output
- unrelated edits
- production changes

Return only:
- finding
- blocker
- next action
```

Default edit prompt:

```text
Task:
- one concrete objective

Allowed:
- explicit files or directories
- bounded edits only

Forbidden:
- secrets output
- unrelated edits
- architecture redesign
- production changes unless explicitly allowed

Return only:
- changed files
- fixes
- risks
- validation
- next manual action
```

## Execution Rules

- One worker per subtask.
- One prompt per worker invocation.
- Read prompts from command args or stdin only.
- Do not bypass the wrapper with raw CLI calls unless debugging the wrapper itself.
- Do not paste secrets into prompts.
- Do not ask the worker to make final release or production decisions.
- If a worker lacks environment, report the missing prerequisite instead of retrying blindly.

## Result Handoff

After worker execution:

1. capture the raw worker output
2. pass the output back to the manager
3. let the manager decide:
   - accepted
   - rejected
   - incomplete
   - needs another round
   - fallback to Codex direct execution

Workers never decide completion.

The wrapper exports these environment variables to the invoked CLI:

- `ORCHESTRATION_WORKER`
- `ORCHESTRATION_TARGET_NAME`
- `ORCHESTRATION_TARGET_GROUP`
- `ORCHESTRATION_TARGET_ROLE`
- `ORCHESTRATION_TARGET_EXECUTION_POLICY`

## Failure Handling

Treat these as worker failures:

- missing CLI dependency
- missing model or API key
- prompt ignored
- output format violated
- result not actionable
- result conflicts with direct repo or runtime evidence

If all worker paths for the round fail, hand control back to the orchestrator and let Codex execute the smallest blocked step directly.

## Output Discipline

Managers should reject worker output when:

- the worker prints secrets
- the worker ignores the requested output shape
- the worker expands scope
- the worker claims success without evidence

Managers should prefer a new smaller follow-up prompt over a larger retry.

## Notes

- Keep this skill thin. It should define worker execution, not planning policy.
- Keep the single source of truth for execution entrypoints in `run_worker.sh`.
- Keep the single source of truth for model defaults in `openclaw_cli_defaults.py`.
- Keep the single source of truth for manager and worker roles in `config/orchestration/roles.yaml`.
