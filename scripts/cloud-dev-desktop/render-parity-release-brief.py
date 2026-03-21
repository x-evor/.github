#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import yaml


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def load_state(state_root: Path, provider: str, profile_name: str) -> dict[str, Any] | None:
    state_path = state_root / f"{provider}-{profile_name}.json"
    if not state_path.exists():
        return None
    with state_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def render_host_rows(manifest: dict[str, Any], state_root: Path) -> list[str]:
    rows = [
        "| Host | Provider | Profile | Request File | Public IP | Desktop Access | State |",
        "|---|---|---|---|---|---|---|",
    ]
    for host_name, host in (manifest.get("hosts") or {}).items():
        provider = str(host.get("provider", "")).strip()
        profile_name = str(host.get("profile_name", "")).strip()
        request_file = str(host.get("request_file", "")).strip()
        state = load_state(state_root, provider, profile_name)
        public_ip = (state or {}).get("public_ip", "pending")
        desktop_access = (state or {}).get("desktop_access", {})
        if isinstance(desktop_access, dict):
            protocol = desktop_access.get("protocol", "pending")
            port = desktop_access.get("port", "pending")
            desktop_value = f"{protocol}:{port}"
        else:
            desktop_value = "pending"
        state_value = "ready" if state else "missing"
        rows.append(
            f"| {host_name} | {provider} | {profile_name} | `{request_file}` | "
            f"{public_ip} | {desktop_value} | {state_value} |"
        )
    return rows


def render_task_rows(manifest: dict[str, Any]) -> list[str]:
    rows = [
        "| Task | Branch | Host | Worktree | Validation Focus |",
        "|---|---|---|---|---|",
    ]
    for task in manifest.get("tasks") or []:
        rows.append(
            f"| {task.get('name', '')} | `{task.get('branch', '')}` | "
            f"{task.get('host', '')} | `{task.get('worktree_name', '')}` | "
            f"{task.get('validation_focus', '')} |"
        )
    return rows


def render_constraints(manifest: dict[str, Any]) -> list[str]:
    constraints = manifest.get("constraints") or []
    if not constraints:
        return [
            "- Keep macOS and iOS behavior unchanged unless a shared abstraction change is required.",
            "- Use one dedicated git worktree per parity lane.",
            "- Push only to the assigned parity branch for each lane.",
        ]
    return [f"- {constraint}" for constraint in constraints]


def render_task_commands(manifest: dict[str, Any]) -> list[str]:
    repo_name = str(manifest.get("workspace_repo", "workspace-repo")).strip()
    lines = [
        "## Worktree Preparation Commands",
        (
            "Run these on the assigned host after cloning the workspace repo and before starting "
            "lane-specific debugging:"
        ),
        "",
    ]
    for task in manifest.get("tasks") or []:
        branch = str(task.get("branch", "")).strip()
        worktree_name = str(task.get("worktree_name", "")).strip()
        host = str(task.get("host", "")).strip()
        lines.extend(
            [
                f"### {task.get('name', '')}",
                f"- Host: `{host}`",
                "```bash",
                "bash scripts/cloud-dev-desktop/prepare-parity-worktree.sh \\",
                f"  --repo /workspace/{repo_name} \\",
                f"  --branch {branch} \\",
                "  --base-ref origin/main \\",
                f"  --worktree /workspace/{worktree_name}",
                "```",
                "",
            ]
        )
    return lines


def render_brief(manifest: dict[str, Any], state_root: Path) -> str:
    release_name = manifest.get("release_name", "parity-release")
    workspace_repo = manifest.get("workspace_repo", "workspace-repo")
    skill_path = (
        manifest.get("skills_dispatch", {}) or {}
    ).get("orchestrator_skill_path", "~/.codex/skills/architect-orchestrator/")
    host_rows = render_host_rows(manifest, state_root)
    task_rows = render_task_rows(manifest)
    park_hosts = bool((manifest.get("post_actions") or {}).get("park_hosts", False))

    lines = [
        "# Architecture Brief",
        "",
        "## Goal",
        (
            f"Use `{skill_path}` to orchestrate parity validation for "
            f"`{workspace_repo}` without regressing macOS or iOS."
        ),
        "",
        "## Requirements -> Acceptance Evidence",
        *render_constraints(manifest),
        "- Each lane records build/run evidence on its assigned host before push.",
        "- Each completed lane pushes to its designated `codex/*` branch.",
        "- The fleet is parked after the release workflow finishes."
        if park_hosts
        else "- Host parking is disabled in the current manifest.",
        "",
        "## Recommended Design",
        (
            "Use GitHub Actions plus Ansible-backed wrapper scripts for cloud lifecycle, and use "
            "the generated orchestrator brief plus helper scripts for the host-level git worktree "
            "and parity-debug lanes."
        ),
        "",
        "## Host Inventory",
        *host_rows,
        "",
        "## Task Matrix",
        *task_rows,
        "",
        "## Agent Topology",
        "- Local orchestrator: `~/.codex/skills/architect-orchestrator/`",
        "- Remote execution lanes: Azure Windows, GCP Fedora GNOME, GCP Ubuntu KDE",
        "- One git worktree per parity branch/lane",
        "",
        "## Orchestrator Prompt",
        "Use `~/.codex/skills/architect-orchestrator/` and dispatch the following:",
        "",
    ]

    for index, task in enumerate(manifest.get("tasks") or [], start=1):
        lines.extend(
            [
                f"{index}. `{task.get('name', '')}`",
                f"   - Branch: `{task.get('branch', '')}`",
                f"   - Host role: `{task.get('host', '')}`",
                f"   - Worktree name: `{task.get('worktree_name', '')}`",
                f"   - Validation focus: {task.get('validation_focus', '')}",
            ]
        )

    lines.extend(
        [
            "",
            "## Review Loop",
            "- Re-run build/run checks after each fix on the assigned host.",
            "- Re-check for macOS/iOS regression risk before pushing shared changes.",
            "- Do not merge parity fixes back to `main` until each branch has host-specific evidence.",
            "",
            *render_task_commands(manifest),
            "",
            "## Risks and Rollback",
            "- If a host lane fails, keep that host parked rather than destroy it until evidence is collected.",
            "- If a parity branch regresses a shared abstraction, reset or revert only that lane branch.",
            "- Use `parity-release.sh --action destroy` only when the fleet is no longer needed.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--state-root", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    manifest_path = Path(args.manifest).expanduser().resolve()
    state_root = Path(args.state_root).expanduser().resolve()
    brief = render_brief(load_yaml(manifest_path), state_root)

    if args.output:
        output_path = Path(args.output).expanduser()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(brief, encoding="utf-8")
    print(brief, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
