#!/usr/bin/env python3
"""Render an ExternalDNS provider secret from a local .env file without committing secrets."""

from __future__ import annotations

import argparse
from pathlib import Path


SUPPORTED_KEYS = [
    "CF_API_TOKEN",
    "CF_API_KEY",
    "CF_API_EMAIL",
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "CLOUDFLARE_ZONE_ID",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AZURE_SUBSCRIPTION_ID",
    "AZURE_TENANT_ID",
    "AZURE_CLIENT_ID",
    "AZURE_CLIENT_SECRET",
]


def parse_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip("'").strip('"')
    return env


def render_secret(namespace: str, values: dict[str, str]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        "  name: externaldns-provider",
        f"  namespace: {namespace}",
        "type: Opaque",
        "stringData:",
    ]
    for key in SUPPORTED_KEYS:
        if key in values:
            lines.append(f"  {key}: \"{values[key]}\"")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", required=True)
    parser.add_argument("--namespace", default="infra-system")
    parser.add_argument("--output")
    parser.add_argument(
        "--keys",
        help="Comma-separated env keys to include. Defaults to a built-in provider key allowlist.",
    )
    args = parser.parse_args()

    env_file = Path(args.env_file)
    values = parse_env(env_file)
    allowed_keys = SUPPORTED_KEYS
    if args.keys:
        allowed_keys = [key.strip() for key in args.keys.split(",") if key.strip()]

    selected = {key: value for key, value in values.items() if key in allowed_keys}

    if not selected:
        raise SystemExit("No supported DNS provider keys were found in the provided .env file.")

    content = render_secret(args.namespace, selected)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(content)
        print(f"Wrote ExternalDNS secret manifest to {output_path}")
    else:
        print(content, end="")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
