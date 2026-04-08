#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-}"
shift || true

ARTIFACT_ROOT="${RUNNER_TEMP:-/tmp}/agent-loop"
mkdir -p "$ARTIFACT_ROOT"

FEATURE_NAME="${FEATURE_NAME:-}"
FEATURE_ID="${FEATURE_ID:-}"
FEATURE_NOTES="${FEATURE_NOTES:-}"
REPO_SCOPE="${REPO_SCOPE:-xworkmate.svc.plus,accounts.svc.plus,github-org-cloud-neutral-toolkit}"
PR_NUMBER="${PR_NUMBER:-}"
EVENT_SOURCE="${EVENT_SOURCE:-github-actions}"

case "$MODE" in
  pr)
    TARGET="${1:?target is required}"
    ENV_NAME="${2:-dev}"
    exec go run ./cmd/full-stack-test run --mcp="$TARGET" --suite=smoke --env="$ENV_NAME" --intent=smoke --event=pr --event-source="$EVENT_SOURCE" --repo-scope="$REPO_SCOPE" --pr-number="$PR_NUMBER" --feature-name="$FEATURE_NAME" --feature-id="$FEATURE_ID" --feature-notes="$FEATURE_NOTES" --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/${TARGET}.json" --artifact-dir="${ARTIFACT_ROOT}/${TARGET}"
    ;;
  release)
    TARGET="${1:?target is required}"
    ENV_NAME="${2:-pre}"
    exec go run ./cmd/full-stack-test run --mcp="$TARGET" --suite=e2e --env="$ENV_NAME" --intent=full --event=release --event-source="$EVENT_SOURCE" --repo-scope="$REPO_SCOPE" --feature-name="$FEATURE_NAME" --feature-id="$FEATURE_ID" --feature-notes="$FEATURE_NOTES" --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/${TARGET}.json" --artifact-dir="${ARTIFACT_ROOT}/${TARGET}"
    ;;
  pr-full)
    ENV_NAME="${1:-dev}"
    exec go run ./cmd/full-stack-test run --event=pr --event-source="$EVENT_SOURCE" --suite=smoke --env="$ENV_NAME" --intent=smoke --repo-scope="$REPO_SCOPE" --pr-number="$PR_NUMBER" --feature-name="$FEATURE_NAME" --feature-id="$FEATURE_ID" --feature-notes="$FEATURE_NOTES" --agent-loop=true --json-out="${RUNNER_TEMP:-/tmp}/pr-full.json" --artifact-dir="${ARTIFACT_ROOT}/pr-full"
    ;;
  *)
    echo "usage: $0 <pr|release|pr-full> [target] [env]" >&2
    exit 2
    ;;
esac
