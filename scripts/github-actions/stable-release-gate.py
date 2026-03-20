#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
WORKSPACE_PATH = ROOT_DIR / "console.svc.plus.code-workspace"
INVENTORY_PATH = ROOT_DIR / "ansible" / "inventory.ini"
SERVICES_COMMON_PATH = ROOT_DIR / "config" / "single-node-release" / "services" / "common.yaml"
REPOSITORIES_PATH = ROOT_DIR / "config" / "single-node-release" / "repositories.json"
RELEASE_CHECKLIST_PATH = ROOT_DIR / "docs" / "operations-governance" / "release-checklist.md"
CROSS_REPO_TASKS_PATH = ROOT_DIR / "docs" / "operations-governance" / "cross-repo-tasks.md"
CONTROL_PLANE_WORKFLOW_PATH = (
    ROOT_DIR / "docs" / "operations-governance" / "service-release-control-plane-workflow.md"
)
METADATA_SCRIPT = ROOT_DIR / "scripts" / "github-actions" / "release-service-metadata.py"


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"missing required file: {path}") from exc


def load_metadata(service: str, track: str, repo_owner: str, service_ref: str) -> dict[str, str]:
    cmd = [
        sys.executable,
        str(METADATA_SCRIPT),
        service,
        track,
        repo_owner,
        str(ROOT_DIR),
        str(INVENTORY_PATH),
        str(WORKSPACE_PATH),
        str(SERVICES_COMMON_PATH),
        str(REPOSITORIES_PATH),
    ]
    completed = subprocess.run(cmd, capture_output=True, text=True, check=True)
    metadata: dict[str, str] = {}
    for raw_line in completed.stdout.splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        metadata[key] = value
    metadata["service_ref"] = service_ref
    return metadata


def ensure_documentation_mentions_gate() -> None:
    release_checklist = load_text(RELEASE_CHECKLIST_PATH)
    cross_repo_tasks = load_text(CROSS_REPO_TASKS_PATH)
    workflow_doc = load_text(CONTROL_PLANE_WORKFLOW_PATH)

    required_fragments = [
        (
            RELEASE_CHECKLIST_PATH,
            [
                "scripts/github-actions/stable-release-gate.py --mode local",
                "scripts/github-actions/stable-release-gate.py --mode stable",
            ],
        ),
        (
            CROSS_REPO_TASKS_PATH,
            [
                "Validation mode:",
                "Gate entry:",
                ".github/workflows/stable_release_gate.yml",
            ],
        ),
        (
            CONTROL_PLANE_WORKFLOW_PATH,
            [
                "stable_release_gate.yml",
                "mode=local",
                "mode=stable",
            ],
        ),
    ]

    for path, fragments in required_fragments:
        text = {
            RELEASE_CHECKLIST_PATH: release_checklist,
            CROSS_REPO_TASKS_PATH: cross_repo_tasks,
            CONTROL_PLANE_WORKFLOW_PATH: workflow_doc,
        }[path]
        missing = [fragment for fragment in fragments if fragment not in text]
        if missing:
            raise SystemExit(f"{path} is missing required release-gate text: {', '.join(missing)}")


def smoke_url_for(metadata: dict[str, str], override_url: str) -> str:
    if override_url:
        return override_url
    return f"https://{metadata['stable_domain']}{metadata['healthcheck_path']}"


def run_http_smoke(url: str, timeout_seconds: int) -> tuple[int, str]:
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            body = response.read(4096).decode("utf-8", errors="replace")
            return response.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read(4096).decode("utf-8", errors="replace")
        raise SystemExit(f"stable smoke failed for {url}: HTTP {exc.code} {body}".strip()) from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"stable smoke failed for {url}: {exc.reason}") from exc


def write_summary(mode: str, service: str, track: str, service_ref: str, message: str) -> None:
    summary_path = Path(os.environ["GITHUB_STEP_SUMMARY"]) if "GITHUB_STEP_SUMMARY" in os.environ else None
    if summary_path is None:
        return
    with summary_path.open("a", encoding="utf-8") as handle:
        handle.write(f"## Stable Release Gate\n")
        handle.write(f"- mode: `{mode}`\n")
        handle.write(f"- service: `{service}`\n")
        handle.write(f"- track: `{track}`\n")
        handle.write(f"- service ref: `{service_ref}`\n")
        handle.write(f"- result: `{message}`\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["local", "stable"], required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--track", choices=["prod", "preview"], required=True)
    parser.add_argument("--service-ref", required=True)
    parser.add_argument("--repo-owner", default="cloud-neutral-toolkit")
    parser.add_argument("--stable-url", default="")
    parser.add_argument("--timeout-seconds", type=int, default=10)
    args = parser.parse_args()

    ensure_documentation_mentions_gate()
    metadata = load_metadata(args.service, args.track, args.repo_owner, args.service_ref)

    if args.mode == "local":
        message = (
            "local checks passed: docs mention the gate workflow, metadata resolved, and stable smoke was skipped"
        )
        print(message)
        write_summary(args.mode, args.service, args.track, args.service_ref, message)
        return 0

    url = smoke_url_for(metadata, args.stable_url)
    status, _body = run_http_smoke(url, args.timeout_seconds)
    if not 200 <= status < 300:
        raise SystemExit(f"stable smoke failed for {url}: HTTP {status}")

    message = f"stable smoke passed against {url} with HTTP {status}"
    print(message)
    write_summary(args.mode, args.service, args.track, args.service_ref, message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
