#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <repo-path> <replace-text-file> [path-to-remove...]" >&2
  exit 1
fi

repo_path=$1
replace_text_file=$2
shift 2
remove_paths=("$@")

if [[ ! -d "$repo_path/.git" ]]; then
  echo "Error: not a git repository: $repo_path" >&2
  exit 1
fi

if [[ ! -f "$replace_text_file" ]]; then
  echo "Error: replace-text file not found: $replace_text_file" >&2
  exit 1
fi

if ! command -v git-filter-repo >/dev/null 2>&1 && ! command -v git >/dev/null 2>&1; then
  echo "Error: git-filter-repo is not installed." >&2
  exit 1
fi

python3 - "$repo_path" <<'PY'
from pathlib import Path
import sys

marker = Path(sys.argv[1]) / ".git/filter-repo/already_ran"
if marker.exists():
    marker.unlink()
PY

cmd=(
  git
  -C "$repo_path"
  filter-repo
  --force
  --sensitive-data-removal
  --replace-text "$replace_text_file"
)

if [[ ${#remove_paths[@]} -gt 0 ]]; then
  for path in "${remove_paths[@]}"; do
    cmd+=(--path "$path")
  done
  cmd+=(--invert-paths)
fi

"${cmd[@]}"
