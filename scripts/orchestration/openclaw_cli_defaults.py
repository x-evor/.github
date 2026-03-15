#!/usr/bin/env python3
"""Read ~/.openclaw/openclaw.json and emit safe CLI default mappings.

This script is intentionally read-only:
- it never writes to user config files
- it never prints provider api keys
- it only exposes model/provider ids that are safe to reference in commands
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


OPENCLAW_PATH = Path.home() / ".openclaw" / "openclaw.json"


def load_openclaw(path: Path) -> dict:
    return json.loads(path.read_text())


def map_opencode_model(model: str) -> str:
    """Translate OpenClaw-style ids to opencode-compatible ids when possible."""
    if model.startswith("api-svc-plus/"):
        _, model_id = model.split("/", 1)
        return f"nvidia/{model_id}"
    if model.startswith("svc-plus/"):
        _, model_id = model.split("/", 1)
        return f"nvidia/{model_id}"
    return model


def build_defaults(cfg: dict) -> dict:
    primary = cfg.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
    ollama_models = [
        m.get("id", "")
        for m in cfg.get("models", {}).get("providers", {}).get("ollama", {}).get("models", [])
        if m.get("id")
    ]

    return {
        "codex": {
            "default_model": "gpt-5.4",
            "reason": "chief engineer / final acceptance",
            "example": 'codex -m "gpt-5.4"',
        },
        "opencode": {
            "default_model": map_opencode_model(primary) if primary else "nvidia/minimaxai/minimax-m2.5",
            "reason": "bounded edits / worker execution",
            "example": f'opencode run --model "{map_opencode_model(primary) if primary else "nvidia/minimaxai/minimax-m2.5"}" "<prompt>"',
        },
        "ollama": {
            "default_model": "glm-5:cloud" if "glm-5:cloud" in ollama_models else (ollama_models[0] if ollama_models else ""),
            "reason": "cheap review / smoke checks",
            "example": 'printf \'%s\\n\' "<prompt>" | ollama run "glm-5:cloud"',
        },
        "gemini": {
            "default_model": "gemini-2.5-flash",
            "reason": "independent read-only audit",
            "example": 'gemini -m "gemini-2.5-flash" "<prompt>"',
            "note": "Gemini does not read OpenClaw provider config; it keeps its own default model and credentials.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=["json", "shell", "markdown"], default="markdown")
    args = parser.parse_args()

    cfg = load_openclaw(OPENCLAW_PATH)
    defaults = build_defaults(cfg)

    if args.format == "json":
        print(json.dumps(defaults, indent=2))
        return 0

    if args.format == "shell":
        print(f'CODEX_DEFAULT_MODEL="{defaults["codex"]["default_model"]}"')
        print(f'OPENCODE_DEFAULT_MODEL="{defaults["opencode"]["default_model"]}"')
        print(f'OLLAMA_DEFAULT_MODEL="{defaults["ollama"]["default_model"]}"')
        print(f'GEMINI_DEFAULT_MODEL="{defaults["gemini"]["default_model"]}"')
        return 0

    print("# CLI Defaults From OpenClaw")
    print()
    for cli in ["codex", "opencode", "ollama", "gemini"]:
        item = defaults[cli]
        print(f"## {cli}")
        print(f'- default model: `{item["default_model"]}`')
        print(f'- role: {item["reason"]}')
        print(f'- example: `{item["example"]}`')
        if "note" in item:
            print(f'- note: {item["note"]}')
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
