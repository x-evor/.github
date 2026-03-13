#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/orchestration/run_manager.sh [--describe] [--print-prompt] [--prompt-mode compact|full] [--template review|deploy|dns-audit] <codex|opencode|antigravity> [task...]

Behavior:
  - reads manager role and execution policy from config/orchestration/roles.yaml
  - loads orchestration skills as manager instructions
  - defaults to a compact prompt mode to reduce token usage
  - supports compact task templates for common manager flows
  - runs codex/opencode headlessly
  - for antigravity, writes a prompt file and opens it in Antigravity
  - if no task arguments are provided, reads task from stdin

Examples:
  scripts/orchestration/run_manager.sh --describe codex
  scripts/orchestration/run_manager.sh --prompt-mode compact --template dns-audit codex "Prepare worker commands for DNS verification."
  scripts/orchestration/run_manager.sh --prompt-mode full opencode "Prepare worker commands for DNS verification."
  scripts/orchestration/run_manager.sh --template review opencode "Review this rollout plan."
  printf '%s\n' "Split this migration validation into worker prompts." | scripts/orchestration/run_manager.sh codex
  scripts/orchestration/run_manager.sh antigravity "Review the rollout plan and prepare worker commands."
EOF
}

resolve_manager_key() {
  case "$1" in
    codex) echo "codex_app" ;;
    opencode) echo "opencode" ;;
    antigravity) echo "antigravity" ;;
    *) return 1 ;;
  esac
}

DESCRIBE=0
PRINT_PROMPT=0
PROMPT_MODE="compact"
TEMPLATE="review"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --describe)
      DESCRIBE=1
      shift
      ;;
    --print-prompt)
      PRINT_PROMPT=1
      shift
      ;;
    --prompt-mode)
      PROMPT_MODE="${2:-}"
      shift 2
      ;;
    --prompt-mode=*)
      PROMPT_MODE="${1#*=}"
      shift
      ;;
    --template)
      TEMPLATE="${2:-}"
      shift 2
      ;;
    --template=*)
      TEMPLATE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

case "$PROMPT_MODE" in
  compact|full) ;;
  *)
    echo "unknown prompt mode: $PROMPT_MODE" >&2
    usage >&2
    exit 2
    ;;
esac

case "$TEMPLATE" in
  review|deploy|dns-audit) ;;
  *)
    echo "unknown template: $TEMPLATE" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ $# -lt 1 ]]; then
  usage
  exit 0
fi

MANAGER="$1"
shift || true
ROLE_KEY="$(resolve_manager_key "$MANAGER")" || {
  echo "unknown manager: $MANAGER" >&2
  usage >&2
  exit 2
}

if [[ $# -gt 0 ]]; then
  TASK_TEXT="$*"
else
  TASK_TEXT="$(cat)"
fi

eval "$(python3 "$ROOT_DIR/scripts/orchestration/openclaw_cli_defaults.py" --format shell)"
eval "$(python3 "$ROOT_DIR/scripts/orchestration/orchestration_roles.py" "$ROLE_KEY" --format shell --shell-prefix ORCHESTRATION_MANAGER)"

export ORCHESTRATION_MANAGER_NAME
export ORCHESTRATION_MANAGER_GROUP
export ORCHESTRATION_MANAGER_ROLE
export ORCHESTRATION_MANAGER_EXECUTION_POLICY
export ORCHESTRATION_MANAGER_BIN="$MANAGER"

case "$MANAGER" in
  codex) DEFAULT_MODEL="$CODEX_DEFAULT_MODEL" ;;
  opencode) DEFAULT_MODEL="$OPENCODE_DEFAULT_MODEL" ;;
  antigravity) DEFAULT_MODEL="" ;;
esac

if [[ "$DESCRIBE" == "1" ]]; then
  cat <<EOF
manager=$MANAGER
default_model=$DEFAULT_MODEL
target_name=$ORCHESTRATION_MANAGER_NAME
target_group=$ORCHESTRATION_MANAGER_GROUP
target_role=$ORCHESTRATION_MANAGER_ROLE
execution_policy=$ORCHESTRATION_MANAGER_EXECUTION_POLICY
prompt_mode=$PROMPT_MODE
template=$TEMPLATE
EOF
  exit 0
fi

if [[ -z "${TASK_TEXT// }" ]]; then
  echo "task is required" >&2
  exit 1
fi

ORCH_SKILL="$ROOT_DIR/skills/codex-multi-cli-orchestrator/SKILL.md"
RUN_TASK_SKILL="$ROOT_DIR/skills/orchestration-run-task/SKILL.md"
MANAGER_REF="$ROOT_DIR/skills/orchestration-run-task/references/manager-integration.md"

build_compact_prompt() {
  case "$TEMPLATE" in
    review)
      TEMPLATE_BLOCK="$(cat <<'EOF'
Template:
- review

Manager output contract:
1. task split
2. worker assignment
3. exact run_worker.sh commands
4. review criteria
5. fallback condition
EOF
)"
      ;;
    deploy)
      TEMPLATE_BLOCK="$(cat <<'EOF'
Template:
- deploy

Manager output contract:
1. stage plan
2. worker assignment
3. exact run_worker.sh commands
4. validation gate
5. rollback gate
6. fallback condition
EOF
)"
      ;;
    dns-audit)
      TEMPLATE_BLOCK="$(cat <<'EOF'
Template:
- dns-audit

Manager output contract:
1. scope
2. worker assignment
3. exact run_worker.sh commands
4. read-only validation gate
5. permission blocker
6. fallback condition
EOF
)"
      ;;
  esac
  cat <<EOF
Follow the local orchestration contract.

Execution loop:
- analyze
- plan
- assign the shortest clear worker prompts
- collect worker outputs
- verify against repo or runtime state
- if complete, stop
- if incomplete, emit the next smallest prompts
- if all worker paths fail, fallback to Codex direct execution only for the smallest blocked step

Manager policy:
- manager bin: $MANAGER
- manager target: $ORCHESTRATION_MANAGER_NAME
- manager role: $ORCHESTRATION_MANAGER_ROLE
- execution policy: $ORCHESTRATION_MANAGER_EXECUTION_POLICY
- prompt mode: $PROMPT_MODE
- template: $TEMPLATE
- workspace root: $ROOT_DIR

Worker entrypoint:
- use scripts/orchestration/run_worker.sh as the only worker command
- do not bypass the wrapper
- do not duplicate model selection logic
- do not duplicate role assignment logic

Role map:
- codex_app: chief engineer and acceptance gate
- codex_cli: direct executor for fallback-only work
- opencode: optional orchestration manager
- antigravity: optional automation manager
- opencode_cli: bounded editor worker
- gemini_cli: independent auditor worker
- ollama: cheap reviewer worker

Worker prompt contract:
- include Task
- include Allowed
- include Forbidden
- include Return only

Failure handling:
- treat missing CLI, missing API key, ignored prompt, bad output shape, and non-actionable output as worker failure
- if worker output conflicts with direct evidence, distrust the worker output

$TEMPLATE_BLOCK

Task:
$TASK_TEXT
EOF
}

build_full_prompt() {
  cat <<EOF
Follow these local skills as the execution contract.

=== BEGIN SKILL: codex-multi-cli-orchestrator ===
$(cat "$ORCH_SKILL")
=== END SKILL ===

=== BEGIN SKILL: orchestration-run-task ===
$(cat "$RUN_TASK_SKILL")
=== END SKILL ===

=== BEGIN REFERENCE: manager-integration ===
$(cat "$MANAGER_REF")
=== END REFERENCE ===

Manager context:
- manager bin: $MANAGER
- manager target: $ORCHESTRATION_MANAGER_NAME
- manager role: $ORCHESTRATION_MANAGER_ROLE
- execution policy: $ORCHESTRATION_MANAGER_EXECUTION_POLICY
- prompt mode: $PROMPT_MODE
- template: $TEMPLATE
- workspace root: $ROOT_DIR

Task:
$TASK_TEXT
EOF
}

if [[ "$PROMPT_MODE" == "compact" ]]; then
  MANAGER_PROMPT="$(build_compact_prompt)"
else
  MANAGER_PROMPT="$(build_full_prompt)"
fi

if [[ "$PRINT_PROMPT" == "1" ]]; then
  printf '%s\n' "$MANAGER_PROMPT"
  exit 0
fi

case "$MANAGER" in
  codex)
    exec codex exec -m "$CODEX_DEFAULT_MODEL" \
      --dangerously-bypass-approvals-and-sandbox \
      -C "$ROOT_DIR" \
      "$MANAGER_PROMPT"
    ;;
  opencode)
    exec opencode run --model "$OPENCODE_DEFAULT_MODEL" "$MANAGER_PROMPT"
    ;;
  antigravity)
    PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/orchestration-manager-antigravity.XXXXXX.md")"
    cat >"$PROMPT_FILE" <<EOF
$MANAGER_PROMPT
EOF
    echo "antigravity_prompt_file=$PROMPT_FILE"
    exec antigravity "$PROMPT_FILE"
    ;;
esac
