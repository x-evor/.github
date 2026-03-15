#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/orchestration/run_worker.sh [--describe] <codex|opencode|ollama|gemini> [prompt...]

Behavior:
  - reads default models from scripts/orchestration/openclaw_cli_defaults.py
  - reads role and execution policy from config/orchestration/roles.yaml
  - uses the selected worker CLI with its derived default model
  - if no prompt arguments are provided, reads prompt from stdin

Examples:
  scripts/orchestration/run_worker.sh --describe ollama
  scripts/orchestration/run_worker.sh ollama "Summarize current deployment risks."
  printf '%s\n' "Review this runbook." | scripts/orchestration/run_worker.sh opencode
  scripts/orchestration/run_worker.sh codex "Review the Docker Compose migration files."
EOF
}

resolve_role_key() {
  case "$1" in
    codex) echo "codex_cli" ;;
    opencode) echo "opencode_cli" ;;
    ollama) echo "ollama" ;;
    gemini) echo "gemini_cli" ;;
    *) return 1 ;;
  esac
}

DESCRIBE=0
if [[ "${1:-}" == "--describe" ]]; then
  DESCRIBE=1
  shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

WORKER="$1"
shift || true
ROLE_KEY="$(resolve_role_key "$WORKER")" || {
  echo "unknown worker: $WORKER" >&2
  usage >&2
  exit 2
}

eval "$(python3 "$ROOT_DIR/scripts/orchestration/openclaw_cli_defaults.py" --format shell)"
eval "$(python3 "$ROOT_DIR/scripts/orchestration/orchestration_roles.py" "$ROLE_KEY" --format shell --shell-prefix ORCHESTRATION_TARGET)"

export ORCHESTRATION_WORKER="$WORKER"
export ORCHESTRATION_TARGET_GROUP
export ORCHESTRATION_TARGET_NAME
export ORCHESTRATION_TARGET_ROLE
export ORCHESTRATION_TARGET_EXECUTION_POLICY

if [[ "$DESCRIBE" == "1" ]]; then
  case "$WORKER" in
    codex) DEFAULT_MODEL="$CODEX_DEFAULT_MODEL" ;;
    opencode) DEFAULT_MODEL="$OPENCODE_DEFAULT_MODEL" ;;
    ollama) DEFAULT_MODEL="$OLLAMA_DEFAULT_MODEL" ;;
    gemini) DEFAULT_MODEL="$GEMINI_DEFAULT_MODEL" ;;
  esac
  cat <<EOF
worker=$WORKER
default_model=$DEFAULT_MODEL
target_name=$ORCHESTRATION_TARGET_NAME
target_group=$ORCHESTRATION_TARGET_GROUP
target_role=$ORCHESTRATION_TARGET_ROLE
execution_policy=$ORCHESTRATION_TARGET_EXECUTION_POLICY
EOF
  exit 0
fi

if [[ $# -gt 0 ]]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [[ -z "${PROMPT// }" ]]; then
  echo "prompt is required" >&2
  exit 1
fi

case "$WORKER" in
  codex)
    exec codex exec -m "$CODEX_DEFAULT_MODEL" \
      --dangerously-bypass-approvals-and-sandbox \
      -C "$ROOT_DIR" \
      "$PROMPT"
    ;;
  opencode)
    exec opencode run --model "$OPENCODE_DEFAULT_MODEL" "$PROMPT"
    ;;
  ollama)
    printf '%s\n' "$PROMPT" | exec ollama run "$OLLAMA_DEFAULT_MODEL"
    ;;
  gemini)
    exec gemini -m "$GEMINI_DEFAULT_MODEL" -y -s false "$PROMPT"
    ;;
  *)
    echo "unknown worker: $WORKER" >&2
    usage >&2
    exit 2
    ;;
esac
