# Manager Integration

Use this reference only when the manager itself is not Codex and still needs to reuse `orchestration-run-task`.

## Goal

Keep one worker execution contract across multiple managers:

- Codex
- opencode multi-agent
- Antigravity
- other automation managers

The manager should load `SKILL.md`, then generate worker prompts that follow the contract.
Prefer [scripts/orchestration/run_manager.sh](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/scripts/orchestration/run_manager.sh) as the single manager entrypoint.

## Manager Pattern

Use this loop:

1. analyze the task
2. split into bounded subtasks
3. assign one worker per subtask
4. generate the shortest valid prompt
5. call `scripts/orchestration/run_worker.sh`
6. collect results
7. accept, reject, or re-dispatch
8. fallback to Codex only if all worker paths fail

## opencode As Manager

Use `opencode` as a manager when:

- repo-aware decomposition is useful
- multiple bounded edit tasks need worker prompts
- another coding agent should prepare prompts, but not make final acceptance decisions

Pattern:

```text
Load orchestration-run-task as the worker execution contract.
Generate exact worker commands only.
Do not execute them.
Return:
1. task split
2. worker assignment
3. exact run_worker.sh commands
4. acceptance check
```

## Antigravity As Manager

Use `Antigravity` as a manager when:

- retries and automation loops matter
- multi-stage workflow control matters
- long-running orchestration is needed

Pattern:

```text
Load orchestration-run-task as the worker contract.
Use run_worker.sh as the only worker entrypoint.
Keep retries small.
On repeated worker failure, mark the subtask blocked and hand it back to Codex.
```

## Loader Pattern

Most tools do not understand Codex skills natively. Treat the skill file as text and inject it into the manager prompt.

Prefer the wrapper instead of hand-building this prompt:

```bash
scripts/orchestration/run_manager.sh --describe codex
scripts/orchestration/run_manager.sh --prompt-mode compact --template review opencode "Review <objective>"
scripts/orchestration/run_manager.sh --prompt-mode compact --template deploy antigravity "Plan deploy for <objective>"
scripts/orchestration/run_manager.sh --prompt-mode compact --template dns-audit codex "Audit DNS task for <objective>"
scripts/orchestration/run_manager.sh --prompt-mode full codex "Prepare worker commands for <objective>"
```

Example:

```bash
SKILL_PATH="/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/skills/orchestration-run-task/SKILL.md"
MANAGER_PROMPT="$(cat "$SKILL_PATH")

Task:
- prepare worker commands for <objective>"
```

## Non-Negotiable Rules

- do not duplicate model selection logic outside `openclaw_cli_defaults.py`
- do not bypass `run_worker.sh`
- do not let workers decide completion
- do not let managers print secrets
- do not let automation silently expand scope
