# OpenClaw Model Reference

Sanitized from `~/.openclaw/openclaw.json`.
Do not copy secrets from that file.

## Orchestrator Default

- Codex App primary orchestrator model: `GPT 5.4`

## Provider: `api-svc-plus`

- `z-ai/glm5`
- `moonshotai/kimi-k2.5`
- `minimaxai/minimax-m2.5`

## Provider: `svc-plus`

- `z-ai/glm5`

## Provider: `ollama`

- `glm-5:cloud`
- `kimi-k2.5:cloud`
- `qwen3.5:9b`
- `minimax-m2.5:cloud`

## Suggested Use

- strongest worker review: `ollama / glm-5:cloud`
- long-context worker review: `ollama / kimi-k2.5:cloud`
- cheap repeated checks: `ollama / qwen3.5:9b`
- low-cost cloud coding or diagnosis: `api-svc-plus / minimaxai/minimax-m2.5`
- alternate diagnosis: `api-svc-plus / z-ai/glm5`

## Suggested Mapping By Stage

- Compose / APISIX / Caddy review: `ollama / glm-5:cloud` or `ollama / qwen3.5:9b`
- Ansible / GitHub Actions bounded edits: `api-svc-plus / minimaxai/minimax-m2.5`
- Read-only second opinion: `api-svc-plus / z-ai/glm5`
- Long checklist or runbook review: `ollama / kimi-k2.5:cloud`

## Hard Rules

- treat model IDs as config references, not secrets
- never store API keys in the repository
- if a provider path fails in one CLI, retry with another CLI before redesigning the workflow

## Local Helper

Use this read-only helper to derive per-CLI defaults from `~/.openclaw/openclaw.json`:

```bash
python3 scripts/orchestration/openclaw_cli_defaults.py
python3 scripts/orchestration/openclaw_cli_defaults.py --format shell
python3 scripts/orchestration/openclaw_cli_defaults.py --format json
```

Notes:

- `codex` and `ollama` can reuse the OpenClaw model choices directly
- `opencode` may need provider-name translation such as `api-svc-plus/...` -> `nvidia/...`
- `gemini` keeps its own credentials and default model; OpenClaw is only used as orchestration context

Use this thin wrapper to dispatch one worker with the derived defaults:

```bash
scripts/orchestration/run_worker.sh ollama "<prompt>"
scripts/orchestration/run_worker.sh opencode "<prompt>"
scripts/orchestration/run_worker.sh codex "<prompt>"
scripts/orchestration/run_worker.sh gemini "<prompt>"
```
