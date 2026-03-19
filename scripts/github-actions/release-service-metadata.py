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
    else:
        raise SystemExit(f"unsupported source_kind '{source_kind}' for repository '{repo_name}'")

    public_vars_path = service.get("public_vars_path", "")
    resolved_public_vars_path = public_vars_path if public_vars_path else ""

    server_alias = resolve_deploy_server_alias(inventory_path, service)
    deploy_hostname = server_alias.split(".", 1)[0]
    domain = services_catalog["domain"]

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
        "dockerfile_path": service["docker"]["dockerfile_path"],
        "build_context": service["docker"]["build_context"],
        "image_name": service["docker"]["image_name"],
        "service_public_vars_path": resolved_public_vars_path,
        "ansible_vars_secret_name": service.get("ansible_vars_secret_name", ""),
        "secret_env_map_json": json.dumps(service.get("secret_env_map", {}), separators=(",", ":")),
        "shared_stunnel_json": json.dumps(service.get("shared_stunnel", {}), separators=(",", ":")),
        "track_env_json": json.dumps(track_conf.get("env", {}), separators=(",", ":")),
        "deploy_subdomain_prefix": track_conf["release_prefix"],
        "stable_domain": track_conf["stable_domain"],
        "host_port": str(track_conf["host_port"]),
        "container_port": str(service["docker"]["container_port"]),
        "healthcheck_path": service["healthcheck_path"],
        "deploy_server_alias": server_alias,
        "deploy_hostname": deploy_hostname,
        "domain": domain,
    }

    for key, value in output.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
