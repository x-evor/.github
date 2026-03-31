#!/usr/bin/env python3
import sys
from pathlib import Path

import json
import yaml


def load_yaml(path_str: str) -> dict:
    path = Path(path_str)
    try:
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing config file: {path}") from exc
    except yaml.YAMLError as exc:
        raise SystemExit(f"invalid yaml file: {path}: {exc}") from exc
    return loaded or {}


def first_server_alias(inventory_path: str) -> str:
    lines = Path(inventory_path).read_text(encoding="utf-8").splitlines()
    in_server = False
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            in_server = line == "[server]"
            continue
        if in_server:
            return line.split()[0]
    raise SystemExit(f"failed to resolve first server alias from {inventory_path}")


def resolve_deploy_server_alias(inventory_path: str, service: dict) -> str:
    explicit_alias = str(service.get("deploy_server_alias", "")).strip()
    if explicit_alias:
        return explicit_alias
    return first_server_alias(inventory_path)


def require_mapping(parent: dict, key: str, service_name: str) -> dict:
    value = parent.get(key, {})
    if not isinstance(value, dict):
        raise SystemExit(f"service '{service_name}' field '{key}' must be a mapping")
    return value


def to_output_bool(value: object) -> str:
    return "true" if bool(value) else "false"


def main() -> None:
    if len(sys.argv) != 9:
        raise SystemExit(
            "usage: release-service-metadata.py "
            "<service> <track> <repo-owner> <control-repo-dir> <inventory-path> "
            "<workspace-path> <services-common-path> <repositories-path>"
        )

    service_name = sys.argv[1]
    track = sys.argv[2]
    repo_owner = sys.argv[3]
    control_repo_dir = sys.argv[4]
    inventory_path = sys.argv[5]
    workspace_path = sys.argv[6]
    services_common_path = sys.argv[7]
    repositories_path = sys.argv[8]

    workspace = json.loads(Path(workspace_path).read_text(encoding="utf-8"))
    services_catalog = load_yaml(services_common_path)
    repository_catalog = json.loads(Path(repositories_path).read_text(encoding="utf-8"))

    workspace_repo_names = {
        folder.get("name") or Path(folder["path"]).name
        for folder in workspace.get("folders", [])
    }

    services = services_catalog.get("services", {})
    service = services.get(service_name)
    if not service:
        raise SystemExit(f"unsupported service: {service_name}")

    track_catalog_path = Path(services_common_path).parent / f"{track}-{service_name}.yaml"
    track_conf = load_yaml(str(track_catalog_path))
    if track_conf.get("service") != service_name:
        raise SystemExit(f"track catalog {track_catalog_path} does not match service '{service_name}'")
    if track_conf.get("track") != track:
        raise SystemExit(f"track catalog {track_catalog_path} does not match track '{track}'")
    if not track_conf.get("enabled", False):
        raise SystemExit(f"unsupported or disabled track '{track}' for service '{service_name}'")

    repo_name = service["repo_name"]
    repositories = repository_catalog.get("repositories", {})
    repo_entry = repositories.get(repo_name)
    if not repo_entry:
        raise SystemExit(f"repository '{repo_name}' is missing from repository catalog")
    if repo_name not in workspace_repo_names:
        raise SystemExit(f"repository '{repo_name}' is not declared in {workspace_path}")

    effective_repo_owner = repo_owner or services_catalog.get("default_repo_owner", "")
    if not effective_repo_owner:
        raise SystemExit("repo owner is required")

    source_kind = repo_entry.get("source_kind", "remote-checkout")
    workspace_repo_path = repo_entry["workspace_path"]
    if source_kind == "git-submodule":
        service_checkout_path = str(Path(control_repo_dir) / workspace_repo_path)
    elif source_kind == "remote-checkout":
        service_checkout_path = repo_name
    elif source_kind == "control-repo":
        service_checkout_path = control_repo_dir
    else:
        raise SystemExit(f"unsupported source_kind '{source_kind}' for repository '{repo_name}'")

    docker_conf = require_mapping(service, "docker", service_name)
    artifact_mode = str(docker_conf.get("mode", "build")).strip() or "build"
    if artifact_mode not in {"build", "prebuilt", "none"}:
        raise SystemExit(
            f"service '{service_name}' has unsupported docker.mode '{artifact_mode}'"
        )
    if artifact_mode == "build":
        if not str(docker_conf.get("dockerfile_path", "")).strip():
            raise SystemExit(f"service '{service_name}' requires docker.dockerfile_path")
        if not str(docker_conf.get("build_context", "")).strip():
            raise SystemExit(f"service '{service_name}' requires docker.build_context")
        if not str(docker_conf.get("image_name", "")).strip():
            raise SystemExit(f"service '{service_name}' requires docker.image_name")
    if artifact_mode == "prebuilt" and not str(docker_conf.get("image_ref", "")).strip():
        raise SystemExit(f"service '{service_name}' requires docker.image_ref for prebuilt mode")

    release_version_conf = require_mapping(service, "release_version", service_name)
    release_version_strategy = (
        str(release_version_conf.get("strategy", "git-short-commit")).strip()
        or "git-short-commit"
    )
    if release_version_strategy not in {"git-short-commit", "fixed"}:
        raise SystemExit(
            f"service '{service_name}' has unsupported release_version.strategy "
            f"'{release_version_strategy}'"
        )
    release_version_value = str(release_version_conf.get("value", "")).strip()
    if release_version_strategy == "fixed" and not release_version_value:
        raise SystemExit(
            f"service '{service_name}' requires release_version.value for fixed strategy"
        )

    domain_map = services_catalog.get("domain_map", {})
    domain_entry = domain_map.get(service_name, {})
    release_dns_enabled = bool(
        service.get("release_dns_enabled", domain_entry.get("role") != "internal")
    )
    release_dns_prefix = (
        str(service.get("release_dns_prefix", "")).strip()
        or str(domain_entry.get("release_dns_prefix", "")).strip()
        or str(track_conf.get("release_prefix", "")).strip()
    )
    release_vhost_name = (
        str(service.get("release_dns_vhost_name", "")).strip()
        or str(domain_entry.get("release_vhost_name", "")).strip()
    )
    if release_dns_enabled and (not release_dns_prefix or not release_vhost_name):
        raise SystemExit(
            f"service '{service_name}' must define release DNS prefix and vhost name"
        )

    public_vars_path = str(service.get("public_vars_path", "")).strip()
    server_alias = resolve_deploy_server_alias(inventory_path, service)
    domain = str(services_catalog["domain"]).strip()
    stable_domain = str(track_conf.get("stable_domain", "")).strip()
    public_domain = str(domain_entry.get("public_domain") or stable_domain).strip()
    runtime_profile = str(service.get("runtime_profile", "ansible-only")).strip() or "ansible-only"

    output = {
        "repo_owner": effective_repo_owner,
        "repo_name": repo_name,
        "repo_category": service["repo_category"],
        "repo_url": service["repo_url"],
        "service_name": service_name,
        "track": track,
        "service_source_kind": source_kind,
        "service_repository": f"{effective_repo_owner}/{repo_name}",
        "service_workspace_path": workspace_repo_path,
        "service_checkout_path": service_checkout_path,
        "playbook_path": service["playbook_path"],
        "runtime_profile": runtime_profile,
        "artifact_mode": artifact_mode,
        "dockerfile_path": str(docker_conf.get("dockerfile_path", "")).strip(),
        "build_context": str(docker_conf.get("build_context", "")).strip(),
        "image_name": str(docker_conf.get("image_name", "")).strip(),
        "prebuilt_image_ref": str(docker_conf.get("image_ref", "")).strip(),
        "build_prepare_script": str(docker_conf.get("build_prepare_script", "")).strip(),
        "build_args_script": str(docker_conf.get("build_args_script", "")).strip(),
        "service_public_vars_path": public_vars_path,
        "ansible_vars_secret_name": service.get("ansible_vars_secret_name", ""),
        "secret_env_map_json": json.dumps(service.get("secret_env_map", {}), separators=(",", ":")),
        "shared_stunnel_json": json.dumps(service.get("shared_stunnel", {}), separators=(",", ":")),
        "track_env_json": json.dumps(track_conf.get("env", {}), separators=(",", ":")),
        "deploy_subdomain_prefix": str(track_conf.get("release_prefix", "")).strip(),
        "release_dns_enabled": to_output_bool(release_dns_enabled),
        "release_dns_prefix": release_dns_prefix,
        "release_vhost_name": release_vhost_name,
        "release_version_strategy": release_version_strategy,
        "release_version_value": release_version_value,
        "stable_domain": stable_domain,
        "public_domain": public_domain,
        "host_port": str(track_conf.get("host_port", "")).strip(),
        "container_port": str(docker_conf.get("container_port", "")).strip(),
        "healthcheck_path": str(service.get("healthcheck_path", "")).strip(),
        "stable_smoke_enabled": to_output_bool(service.get("stable_smoke_enabled", True)),
        "deploy_server_alias": server_alias,
        "domain": domain,
    }

    for key, value in output.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
