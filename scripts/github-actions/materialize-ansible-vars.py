#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

import yaml


def require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"missing required environment variable: {name}")
    return value


def build_secret_payload() -> dict:
    legacy_secret_name = os.environ.get("SERVICE_ANSIBLE_VARS_SECRET_NAME", "")
    secret_env_map_json = os.environ.get("SERVICE_SECRET_ENV_MAP_JSON", "")

    if legacy_secret_name:
        legacy_secret_value = os.environ.get(legacy_secret_name, "")
        if not legacy_secret_value:
            raise SystemExit(f"Missing GitHub secret payload for {legacy_secret_name}")
        try:
            loaded = yaml.safe_load(legacy_secret_value) or {}
        except yaml.YAMLError as exc:
            raise SystemExit(f"failed to parse legacy vars secret {legacy_secret_name}: {exc}") from exc
        if not isinstance(loaded, dict):
            raise SystemExit(f"legacy vars secret {legacy_secret_name} must be a YAML mapping")
        return loaded

    if not secret_env_map_json or secret_env_map_json == "{}":
        return {}

    try:
        secret_mapping = json.loads(secret_env_map_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid SERVICE_SECRET_ENV_MAP_JSON: {exc}") from exc

    if not isinstance(secret_mapping, dict):
        raise SystemExit("SERVICE_SECRET_ENV_MAP_JSON must decode to an object")

    payload = {"service_compose_env_common": {}}
    for target_env, secret_name in secret_mapping.items():
        secret_value = os.environ.get(secret_name, "")
        if not secret_value:
            raise SystemExit(f"Missing GitHub secret payload for {secret_name}")
        payload["service_compose_env_common"][target_env] = secret_value

    return payload


def build_runtime_payload() -> dict:
    track_env_json = os.environ.get("SERVICE_TRACK_ENV_JSON", "")
    track_env = {}
    if track_env_json:
        try:
            track_env = json.loads(track_env_json)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid SERVICE_TRACK_ENV_JSON: {exc}") from exc
        if not isinstance(track_env, dict):
            raise SystemExit("SERVICE_TRACK_ENV_JSON must decode to an object")

    return {
        "service_compose_image": require_env("SERVICE_COMPOSE_IMAGE"),
        "service_compose_registry_server": os.environ.get("GHCR_REGISTRY", "ghcr.io"),
        "service_compose_registry_username": require_env("GHCR_USERNAME"),
        "service_compose_registry_password": require_env("GHCR_TOKEN"),
        "service_compose_container_port": int(require_env("SERVICE_CONTAINER_PORT")),
        "service_compose_deploy_targets": [
            {
                "name": require_env("SERVICE_LOGICAL_NAME"),
                "deploy_subdomain_prefix": require_env("SERVICE_DEPLOY_PREFIX"),
                "stable_domains": [require_env("SERVICE_STABLE_DOMAIN")],
                "host_port": int(require_env("SERVICE_HOST_PORT")),
                "healthcheck_path": require_env("SERVICE_HEALTHCHECK_PATH"),
                "env": track_env,
            }
        ],
    }


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: materialize-ansible-vars.py <secret-vars-file> <runtime-vars-file>")

    secret_vars_file = Path(sys.argv[1])
    runtime_vars_file = Path(sys.argv[2])

    secret_payload = build_secret_payload()
    runtime_payload = build_runtime_payload()

    secret_vars_file.write_text(yaml.safe_dump(secret_payload, sort_keys=False), encoding="utf-8")
    runtime_vars_file.write_text(yaml.safe_dump(runtime_payload, sort_keys=False), encoding="utf-8")


if __name__ == "__main__":
    main()
