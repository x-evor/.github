#!/usr/bin/env python3
"""Read orchestration role configuration from config/orchestration/roles.yaml.

The file intentionally uses JSON-compatible YAML so we can parse it with the
standard library only.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROLES_PATH = ROOT / "config" / "orchestration" / "roles.yaml"


def load_roles() -> dict:
    return json.loads(ROLES_PATH.read_text())


def iter_entries(data: dict):
    for group in ("managers", "workers"):
        for name, spec in data.get(group, {}).items():
            yield group, name, spec


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("name", nargs="?", help="Optional manager/worker key to print")
    parser.add_argument("--format", choices=["json", "markdown", "shell"], default="markdown")
    parser.add_argument("--shell-prefix", default="", help="Optional variable prefix for --format shell")
    args = parser.parse_args()

    data = load_roles()

    selected = []
    for group, name, spec in iter_entries(data):
        if args.name and name != args.name:
            continue
        selected.append((group, name, spec))

    if args.name and not selected:
        raise SystemExit(f"unknown role target: {args.name}")

    if args.format == "json":
        if args.name:
            group, name, spec = selected[0]
            print(json.dumps({"group": group, "name": name, **spec}, indent=2))
        else:
            print(json.dumps(data, indent=2))
        return 0

    if args.format == "shell":
        for group, name, spec in selected:
            prefix = args.shell_prefix or name.upper().replace("-", "_")
            print(f'{prefix}_GROUP="{group}"')
            print(f'{prefix}_NAME="{name}"')
            print(f'{prefix}_ROLE="{spec["role"]}"')
            print(f'{prefix}_EXECUTION_POLICY="{spec["execution_policy"]}"')
        return 0

    print("# Orchestration Roles")
    print()
    for group, name, spec in selected:
        print(f"## {name}")
        print(f"- group: `{group}`")
        print(f"- role: `{spec['role']}`")
        print(f"- execution policy: `{spec['execution_policy']}`")
        print("- responsibilities:")
        for item in spec.get("responsibilities", []):
            print(f"  - {item}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
