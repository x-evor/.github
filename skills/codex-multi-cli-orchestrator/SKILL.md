---
name: codex-multi-cli-orchestrator
description: Use when Codex App with GPT 5.4 should act as the chief engineer and dispatch low-cost or isolated sub-tasks to ollama, opencode, or gemini CLIs instead of doing all execution itself. Best for migration verification, batch checks, document fixes, and controlled multi-model delegation.
version: 1.0.0
author: Cloud Neutral Toolkit
tags: [codex, orchestration, ollama, opencode, gemini, delegation, multi-cli]
---

# Codex Multi-CLI Orchestrator

## Goal

Codex App + GPT 5.4 is the primary planner, reviewer, and acceptance gate.

Default operating mode:

```text
analyze
  -> plan
  -> assign the shortest clear prompt to each worker
  -> collect worker outputs
  -> verify against real repo/runtime state
  -> if done, stop this round
  -> if failed or incomplete, re-dispatch the next smallest task
  -> if all worker attempts fail, fallback to Codex direct execution
```

Use this skill when Codex should:

- break one objective into smaller tasks
- decide which external CLI should execute each task
- keep risky decisions centralized in Codex
- use cheaper or specialized models for low-risk execution

Codex remains the source of truth. Other CLIs are workers.

## Target Delivery Chain

Use this deployment chain as the default control flow:

```text
GitHub Actions / ansible
  -> Docker Compose / SSH deploy
  -> Docker Host
     - APISIX (standalone)
     - Caddy
     - App containers
  -> Cloudflare DNS
```

Interpretation:

- `GitHub Actions` builds and prepares release inputs
- `ansible` is the only deploy actuator
- `Docker Compose` is the only app runtime path
- `APISIX` and `Caddy` are host-side traffic components
- `Cloudflare DNS` is last-step cutover only

## Command Role Split

Use Codex App + GPT 5.4 for:

- task decomposition
- risk review
- deciding execution order
- checking whether a worker result is trustworthy
- final migration readiness judgment

Use `ollama` for:

- cheap local or cloud-backed review passes
- smoke-check prompts
- short fix proposals
- repeated verification loops
- APISIX / Caddy / compose file review

Use `opencode` for:

- repo-aware coding or editing tasks when you want a second coding agent
- low-risk implementation or mechanical refactors
- bounded file changes with explicit output format
- ansible role or workflow edits within a fixed path boundary

Use `gemini` for:

- short read-only audits
- alternative diagnosis
- summarization of current state
- release checklist cross-checks and command review

Do not let worker CLIs make final production decisions.

## Default Execution Contract

For future execution rounds, use this contract unless the user overrides it:

1. Codex does not execute worker CLIs on the user's behalf by default.
2. Codex only:
   - analyzes the current objective
   - creates the plan
   - assigns the shortest clear prompt to each worker
   - collects and summarizes worker outputs provided by the user
   - decides whether the round is complete or needs re-dispatch
3. The user executes:
   - `scripts/orchestration/run_worker.sh opencode "<prompt>"`
   - `scripts/orchestration/run_worker.sh ollama "<prompt>"`
   - `scripts/orchestration/run_worker.sh gemini "<prompt>"`
4. Codex remains the only final acceptance gate.
5. If all worker attempts fail, or all worker results are incomplete or untrustworthy, Codex may execute the smallest necessary direct validation or implementation step itself.

Use this exact round structure:

1. Analyze
2. Plan
3. Worker prompt assignment
4. User executes workers
5. Codex summarizes worker results
6. Codex checks whether completion criteria are met
7. If complete, end the round
8. If failed or incomplete, dispatch the next smallest follow-up prompts
9. If all worker paths fail, fallback to Codex direct execution for the smallest necessary step

## Model Selection

Read [references/openclaw-models.md](references/openclaw-models.md) before dispatching.
Use [../orchestration-run-task/SKILL.md](../orchestration-run-task/SKILL.md) when turning a subtask into a concrete `run_worker.sh` command.

Default policy:

1. Prefer Codex App + GPT 5.4 as orchestrator.
2. Prefer low-cost worker models for read-only checks.
3. Prefer cloud-backed models over weak local models when accuracy matters.
4. Never copy secrets from `~/.openclaw/openclaw.json` into prompts, logs, docs, or repo files.

## Delegation Rules

Before dispatching:

1. State the exact task boundary.
2. State whether the worker may modify files.
3. State the allowed paths.
4. State forbidden actions.
5. State the output format.

Use this prompt frame:

```text
Task:
- one concrete objective only

Allowed:
- exact files or directories
- read-only or limited edits

Forbidden:
- secrets output
- DNS changes before migration readiness is confirmed
- architecture redesign
- final cutover
- unrelated edits

Return only:
- changed files
- fixes
- risks
- validation
- next manual action
```

When the task is read-only, prefer an even smaller output contract:

```text
Return only:
- finding
- blocker
- next action
```

## Safety Rules

- Follow [../env-secrets-governance/SKILL.md](../env-secrets-governance/SKILL.md) for any env or secret related task.
- Never paste provider `apiKey` values into prompts.
- Prefer non-destructive commands first.
- Prefer worker execution before Codex direct execution whenever the task can be safely delegated.
- Before migration readiness is confirmed, DNS records, DNS provider changes, and registrar-side changes are out of scope.
- After deployment verification is complete, DNS changes may be planned as the final manual migration step if the user explicitly approves them.
- For deployment work, require a dry-run or config validation step before apply.
- If a worker result conflicts with direct execution, trust direct execution.
- If a worker changes control-plane logic, Codex must re-verify it itself.
- If Codex falls back to direct execution, keep the scope to the smallest blocked step and return control to the worker loop afterward when possible.

## Recommended Dispatch Patterns

### Migration Verification

- Codex defines scope and acceptance criteria.
- `ollama` reviews Compose, APISIX, and Caddy config for low-cost issues.
- `opencode` performs bounded fixes in Ansible, workflow, or docs paths.
- `gemini` provides a second read-only review when another opinion is useful.
- Codex summarizes all worker results and decides whether a new round is required.
- If all worker attempts fail, Codex directly validates the blocked step and then resumes the worker-first loop.

### Docker Host Release Flow

Use this default task split:

1. Codex
   - define release scope
   - decide whether task is build, deploy, verify, or docs-only
   - keep DNS blocked until readiness is explicit
2. `ollama`
   - review `docker-compose.yaml`, `apisix.yaml`, `Caddyfile`, and smoke-check commands
3. `opencode`
   - patch Ansible roles, GitHub Actions, and migration docs in bounded paths
4. `gemini`
   - audit command order, acceptance criteria, and rollback wording
5. Codex
   - run final `ansible-playbook`
   - run runtime verification
   - declare whether system is ready for manual Cloudflare DNS approval

### Docs and Runbook Cleanup

- `gemini` or `ollama` drafts corrections.
- `opencode` applies mechanical doc fixes if needed.
- Codex verifies steps against the real repo and runtime behavior.

### Playbook Validation

- Worker reviews role/playbook structure.
- Codex runs `ansible-playbook --syntax-check` or real dry-run.
- Only Codex decides whether the playbook is ready.

## Acceptance Gate

Codex should not mark a task complete until:

1. at least one real command has validated the worker claim, or
2. the task is explicitly documentation-only

For migration work, require:

- rendered config validation
- runtime prerequisite confirmation
- explicit unresolved risks
- explicit statement on whether DNS change is still blocked or is ready for manual approval
- explicit identification of which stage failed: GitHub Actions, ansible, Docker Compose, Docker Host, or Cloudflare handoff

For worker-driven rounds, also require:

- explicit note on which worker result was accepted
- explicit note on which worker result was ignored or distrusted
- explicit next prompt if another round is needed
- explicit note when the round falls back to Codex direct execution

## Notes

- Keep the worker prompt short.
- Prefer one worker per subtask.
- Reuse model names from the OpenClaw config reference rather than inventing new names.
