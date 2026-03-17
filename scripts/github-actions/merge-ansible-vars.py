#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import yaml


def load_yaml(path: Path) -> object:
    if not path.exists():
        raise SystemExit(f"vars file not found: {path}")
    try:
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise SystemExit(f"failed to parse YAML {path}: {exc}") from exc
    return {} if loaded is None else loaded


def deep_merge(base: object, override: object) -> object:
    if isinstance(base, dict) and isinstance(override, dict):
        merged = dict(base)
        for key, value in override.items():
            if key in merged:
                merged[key] = deep_merge(merged[key], value)
            else:
                merged[key] = value
        return merged
    return override


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: merge-ansible-vars.py <output-file> <vars-file> [vars-file...]")

    output_file = Path(sys.argv[1])
    input_paths = [Path(value) for value in sys.argv[2:]]

    merged: object = {}
    for path in input_paths:
        merged = deep_merge(merged, load_yaml(path))

    output_file.write_text(yaml.safe_dump(merged, sort_keys=False), encoding="utf-8")


if __name__ == "__main__":
    main()
