#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def load_json(path_str: str) -> dict:
    path = Path(path_str)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing config file: {path}") from exc


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


def main() -> None:
    if len(sys.argv) != 8:
        raise SystemExit(
            "usage: release-service-metadata.py "
            "<service> <track> <repo-owner> <inventory-path> "
            "<workspace-path> <services-path> <repositories-path>"
        )

    service_name = sys.argv[1]
    track = sys.argv[2]
    repo_owner = sys.argv[3]
    inventory_path = sys.argv[4]
    workspace_path = sys.argv[5]
    services_path = sys.argv[6]
    repositories_path = sys.argv[7]

    workspace = load_json(workspace_path)
    services_catalog = load_json(services_path)
    repository_catalog = load_json(repositories_path)

    workspace_repo_names = {
        folder.get("name") or Path(folder["path"]).name
        for folder in workspace.get("folders", [])
    }

    services = services_catalog.get("services", {})
    service = services.get(service_name)
    if not service:
        raise SystemExit(f"unsupported service: {service_name}")

    tracks = service.get("tracks", {})
    track_conf = tracks.get(track)
    if not track_conf or not track_conf.get("enabled", False):
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

    server_alias = first_server_alias(inventory_path)
    deploy_hostname = server_alias.split(".", 1)[0]
    domain = services_catalog["domain"]

    output = {
        "repo_owner": effective_repo_owner,
        "repo_name": repo_name,
        "repo_category": service["repo_category"],
        "repo_url": service["repo_url"],
        "service_name": service_name,
        "track": track,
        "service_repository": f"{effective_repo_owner}/{repo_name}",
        "service_checkout_path": repo_name,
        "playbook_path": service["playbook_path"],
        "dockerfile_path": service["docker"]["dockerfile_path"],
        "build_context": service["docker"]["build_context"],
        "image_name": service["docker"]["image_name"],
        "deploy_subdomain_prefix": track_conf["release_prefix"],
        "stable_domain": track_conf["stable_domain"],
        "host_port": str(track_conf["host_port"]),
        "container_port": str(service["docker"]["container_port"]),
        "healthcheck_path": service["healthcheck_path"],
        "deploy_server_alias": server_alias,
        "deploy_hostname": deploy_hostname,
        "domain": domain,
        "ansible_vars_secret_name": service["ansible_vars_secret_name"],
    }

    for key, value in output.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
