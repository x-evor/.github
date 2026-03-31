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
    runtime_profile = os.environ.get("SERVICE_RUNTIME_PROFILE", "").strip()
    release_version = os.environ.get("SERVICE_RELEASE_VERSION", "").strip()
    release_version_dns_label = os.environ.get("SERVICE_RELEASE_VERSION_DNS_LABEL", "").strip()
    stable_domain = os.environ.get("SERVICE_STABLE_DOMAIN", "").strip()
    release_domain = os.environ.get("SERVICE_RELEASE_DOMAIN", "").strip()

    track_env_json = os.environ.get("SERVICE_TRACK_ENV_JSON", "")
    track_env = {}
    if track_env_json:
        try:
            track_env = json.loads(track_env_json)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid SERVICE_TRACK_ENV_JSON: {exc}") from exc
        if not isinstance(track_env, dict):
            raise SystemExit("SERVICE_TRACK_ENV_JSON must decode to an object")

    shared_stunnel_json = os.environ.get("SERVICE_SHARED_STUNNEL_JSON", "")
    shared_stunnel = {}
    if shared_stunnel_json:
        try:
            shared_stunnel = json.loads(shared_stunnel_json)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid SERVICE_SHARED_STUNNEL_JSON: {exc}") from exc
        if not isinstance(shared_stunnel, dict):
            raise SystemExit("SERVICE_SHARED_STUNNEL_JSON must decode to an object")

    runtime_payload = {
        "service_name": os.environ.get("SERVICE_NAME", "").strip(),
        "service_runtime_profile": runtime_profile,
        "service_image_ref": os.environ.get("SERVICE_COMPOSE_IMAGE", "").strip(),
        "service_release_version": release_version,
        "service_release_version_dns_label": release_version_dns_label,
        "service_release_domain": release_domain,
        "service_public_domain": os.environ.get("SERVICE_PUBLIC_DOMAIN", "").strip(),
        "service_stable_domain": stable_domain,
        "service_healthcheck_path": os.environ.get("SERVICE_HEALTHCHECK_PATH", "").strip(),
        "service_release_dns_enabled": os.environ.get("SERVICE_RELEASE_DNS_ENABLED", "false").strip().lower() == "true",
        "service_release_dns_service_name": os.environ.get("SERVICE_RELEASE_DNS_SERVICE_NAME", "").strip(),
        "service_release_vhost_name": os.environ.get("SERVICE_RELEASE_VHOST_NAME", "").strip(),
        "service_release_domains": [value for value in [stable_domain, release_domain] if value],
    }

    if runtime_profile == "shared-compose":
        runtime_payload.update(
            {
                "service_compose_image": require_env("SERVICE_COMPOSE_IMAGE"),
                "service_compose_registry_server": os.environ.get("GHCR_REGISTRY", "ghcr.io"),
                "service_compose_registry_username": require_env("GHCR_USERNAME"),
                "service_compose_registry_password": require_env("GHCR_TOKEN"),
                "service_compose_release_version": release_version_dns_label or release_version,
                "service_compose_release_vhost_name": require_env("SERVICE_RELEASE_VHOST_NAME"),
                "service_compose_container_port": int(require_env("SERVICE_CONTAINER_PORT")),
                "service_compose_deploy_targets": [
                    {
                        "name": require_env("SERVICE_LOGICAL_NAME"),
                        "deploy_subdomain_prefix": require_env("SERVICE_DEPLOY_PREFIX"),
                        "stable_domains": [stable_domain] if stable_domain else [],
                        "host_port": int(require_env("SERVICE_HOST_PORT")),
                        "healthcheck_path": require_env("SERVICE_HEALTHCHECK_PATH"),
                        "env": track_env,
                    }
                ],
                "service_compose_shared_stunnel_enabled": bool(shared_stunnel.get("enabled", False)),
                "service_compose_shared_stunnel_container_name": str(
                    shared_stunnel.get("container_name", "cn-toolkit-stunnel-client")
                ),
                "service_compose_shared_stunnel_network_name": str(
                    shared_stunnel.get("network_name", "cn-toolkit-shared")
                ),
                "service_compose_shared_stunnel_image": str(
                    shared_stunnel.get("image", "dweomer/stunnel")
                ),
                "service_compose_shared_stunnel_accept_port": int(
                    shared_stunnel.get("accept_port", 15432)
                ),
            }
        )
    return runtime_payload


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
