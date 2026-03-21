#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: prepare-parity-worktree.sh \
  --repo <path> \
  --branch <name> \
  --worktree <path> \
  [--remote <name>] \
  [--base-ref <ref>] \
  [--dry-run]
EOF
  exit 1
}

repo=""
branch=""
worktree=""
remote="origin"
base_ref="origin/main"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --worktree) worktree="$2"; shift 2 ;;
    --remote) remote="$2"; shift 2 ;;
    --base-ref) base_ref="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done

[[ -n "${repo}" && -n "${branch}" && -n "${worktree}" ]] || usage

repo="$(cd "$(dirname "${repo}")" && pwd)/$(basename "${repo}")"
worktree_parent="$(dirname "${worktree}")"
mkdir -p "${worktree_parent}"
worktree="$(cd "${worktree_parent}" && pwd)/$(basename "${worktree}")"

command -v git >/dev/null 2>&1 || {
  echo "missing required command: git" >&2
  exit 1
}

git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null
git -C "${repo}" fetch "${remote}" --prune

start_ref="${base_ref}"

if [[ -e "${worktree}" ]]; then
  if git -C "${repo}" worktree list --porcelain | grep -Fxq "worktree ${worktree}"; then
    echo "worktree already exists: ${worktree}"
    exit 0
  fi
  echo "target path already exists and is not a registered git worktree: ${worktree}" >&2
  exit 1
fi

cmd=(git -C "${repo}" worktree add -B "${branch}" "${worktree}" "${start_ref}")

if [[ "${dry_run}" == "true" ]]; then
  printf 'remote=%s\n' "${remote}"
  printf 'branch=%s\n' "${branch}"
  printf 'start_ref=%s\n' "${start_ref}"
  printf 'worktree=%s\n' "${worktree}"
  printf 'command='
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
