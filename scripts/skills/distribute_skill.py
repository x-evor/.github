#!/usr/bin/env python3
"""Copy a skill from the control repo into target repos and repackage it there."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from package_skill import package_skill
from validate_skill import validate_skill


def sync_file(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def sync_tree(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))


def distribute(source_skill_dir: Path, target_repo_dir: Path, control_repo_dir: Path) -> Path:
    valid, message = validate_skill(source_skill_dir)
    if not valid:
        raise ValueError(f"Source skill invalid: {message}")

    if not (target_repo_dir / ".git").exists():
        raise ValueError(f"Target is not a git repo: {target_repo_dir}")

    skill_name = source_skill_dir.name
    target_skill_dir = target_repo_dir / "skills" / skill_name
    sync_tree(source_skill_dir, target_skill_dir)

    source_scripts_dir = control_repo_dir / "scripts" / "skills"
    target_scripts_dir = target_repo_dir / "scripts" / "skills"
    sync_file(source_scripts_dir / "validate_skill.py", target_scripts_dir / "validate_skill.py")
    sync_file(source_scripts_dir / "package_skill.py", target_scripts_dir / "package_skill.py")

    valid, message = validate_skill(target_skill_dir)
    if not valid:
        raise ValueError(f"Target skill invalid after sync: {message}")

    return package_skill(target_skill_dir, target_repo_dir / "dist" / "skills")


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: distribute_skill.py <source-skill-dir> <target-repo> [target-repo...]", file=sys.stderr)
        return 1

    source_skill_dir = Path(sys.argv[1]).resolve()
    control_repo_dir = Path(__file__).resolve().parents[2]
    if not source_skill_dir.exists():
        print(f"Error: source skill dir not found: {source_skill_dir}", file=sys.stderr)
        return 1

    for target in sys.argv[2:]:
        target_repo_dir = Path(target).resolve()
        packaged = distribute(source_skill_dir, target_repo_dir, control_repo_dir)
        print(f"{target_repo_dir}: {packaged}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
