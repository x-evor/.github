#!/usr/bin/env python3
"""Render sanitized K3s manifests for the core services migration."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = ROOT / "config" / "k3s-migration" / "core-services.json"
SENSITIVE_PATTERN = re.compile(r"(SECRET|TOKEN|KEY|PASSWORD|PASS|DSN|DATABASE_URL|SMTP_|DB_)", re.I)


def load_inventory() -> dict:
    with INVENTORY_PATH.open() as f:
        return json.load(f)


def load_cloud_run_desc(path: Path | None) -> dict | None:
    if not path or not path.exists():
        return None
    with path.open() as f:
        return json.load(f)


def infer_image(service: dict, desc: dict | None) -> str:
    if desc:
        containers = desc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
        if containers:
            return containers[0].get("image", "REPLACE_IMAGE")
    return f"REPLACE_IMAGE_FOR_{service['name'].upper().replace('-', '_')}"


def env_keys_from_example(repo_path: Path) -> list[str]:
    env_file = repo_path / ".env.example"
    if not env_file.exists():
        return []
    keys: list[str] = []
    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        if key:
            keys.append(key)
    return keys


def env_items(service: dict, desc: dict | None) -> list[dict]:
    items: dict[str, dict] = {}
    if desc:
        containers = desc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
        for container in containers:
            if container.get("name", "").endswith("sidecar"):
                continue
            for env in container.get("env", []):
                name = env.get("name")
                if not name:
                    continue
                if "valueFrom" in env or SENSITIVE_PATTERN.search(name):
                    items[name] = {"name": name, "kind": "secret"}
                else:
                    items[name] = {"name": name, "kind": "config", "value": env.get("value", "")}
    for key in env_keys_from_example(Path(service["repo_path"])):
        items.setdefault(
            key,
            {"name": key, "kind": "secret" if SENSITIVE_PATTERN.search(key) else "config", "value": ""},
        )
    return sorted(items.values(), key=lambda item: item["name"])


def render_secret(service: dict, envs: list[dict]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        f"  name: {service['name']}-env",
        f"  namespace: {service['namespace']}",
        "type: Opaque",
        "stringData:",
    ]
    if not envs:
        lines.append("  EXAMPLE_KEY: \"REPLACE_ME\"")
    else:
        for env in envs:
            if env["kind"] == "secret":
                lines.append(f"  {env['name']}: \"REPLACE_ME\"")
    return "\n".join(lines) + "\n"


def render_configmap(service: dict, envs: list[dict]) -> str:
    config_envs = [env for env in envs if env["kind"] == "config"]
    lines = [
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        f"  name: {service['name']}-config",
        f"  namespace: {service['namespace']}",
        "data:",
    ]
    if not config_envs:
        lines.append("  APP_MODE: production")
    else:
        for env in config_envs:
            value = env.get("value") or "REPLACE_ME"
            lines.append(f"  {env['name']}: \"{value}\"")
    return "\n".join(lines) + "\n"


def render_deployment(service: dict, image: str, envs: list[dict]) -> str:
    lines = [
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        f"  name: {service['name']}",
        f"  namespace: {service['namespace']}",
        "spec:",
        "  replicas: 1",
        "  revisionHistoryLimit: 2",
        "  selector:",
        "    matchLabels:",
        f"      app: {service['name']}",
        "      track: stable",
        "  template:",
        "    metadata:",
        "      labels:",
        f"        app: {service['name']}",
        "        track: stable",
        "    spec:",
        "      containers:",
        "        - name: app",
        f"          image: {image}",
        "          imagePullPolicy: IfNotPresent",
        "          ports:",
        f"            - containerPort: {service['container_port']}",
        "          resources:",
        "            requests:",
        f"              cpu: \"{service['recommended_request_cpu_m']}m\"",
        f"              memory: \"{service['recommended_request_memory_mib']}Mi\"",
        "            limits:",
        f"              cpu: \"{service['recommended_limit_cpu_m']}m\"",
        f"              memory: \"{service['recommended_limit_memory_mib']}Mi\"",
        "          envFrom:",
        "            - configMapRef:",
        f"                name: {service['name']}-config",
        "            - secretRef:",
        f"                name: {service['name']}-env",
        "          readinessProbe:",
        "            httpGet:",
        "              path: /healthz",
        f"              port: {service['container_port']}",
        "            initialDelaySeconds: 10",
        "            periodSeconds: 10",
        "          livenessProbe:",
        "            httpGet:",
        "              path: /healthz",
        f"              port: {service['container_port']}",
        "            initialDelaySeconds: 30",
        "            periodSeconds: 20",
    ]
    if envs:
        lines.extend(
            [
                "      # Review all inherited Cloud Run settings before production cutover.",
            ]
        )
    return "\n".join(lines) + "\n"


def render_preview_deployment(service: dict, image: str) -> str:
    return "\n".join(
        [
            "apiVersion: apps/v1",
            "kind: Deployment",
            "metadata:",
            f"  name: {service['name']}-preview",
            f"  namespace: {service['namespace']}",
            "spec:",
            "  replicas: 1",
            "  revisionHistoryLimit: 1",
            "  selector:",
            "    matchLabels:",
            f"      app: {service['name']}",
            "      track: preview",
            "  template:",
            "    metadata:",
            "      labels:",
            f"        app: {service['name']}",
            "        track: preview",
            "    spec:",
            "      containers:",
            "        - name: app",
            f"          image: {image}",
            "          imagePullPolicy: IfNotPresent",
            "          ports:",
            f"            - containerPort: {service['container_port']}",
            "          resources:",
            "            requests:",
            f"              cpu: \"{service['recommended_request_cpu_m']}m\"",
            f"              memory: \"{service['recommended_request_memory_mib']}Mi\"",
            "            limits:",
            f"              cpu: \"{service['recommended_limit_cpu_m']}m\"",
            f"              memory: \"{service['recommended_limit_memory_mib']}Mi\"",
            "          envFrom:",
            "            - configMapRef:",
            f"                name: {service['name']}-config",
            "            - secretRef:",
            f"                name: {service['name']}-env",
        ]
    ) + "\n"


def render_service(service: dict, track: str = "stable") -> str:
    name = service["name"] if track == "stable" else f"{service['name']}-preview"
    return "\n".join(
        [
            "apiVersion: v1",
            "kind: Service",
            "metadata:",
            f"  name: {name}",
            f"  namespace: {service['namespace']}",
            "spec:",
            "  selector:",
            f"    app: {service['name']}",
            f"    track: {track}",
            "  ports:",
            f"    - port: 80",
            f"      targetPort: {service['container_port']}",
            "      protocol: TCP",
        ]
    ) + "\n"


def render_ingress(service: dict, track: str = "stable") -> str:
    name = service["name"] if track == "stable" else f"{service['name']}-preview"
    hostname = service["hostname"] if track == "stable" else service.get("preview_hostname_pattern", "preview-REPLACE_SHA.svc.plus").replace("<sha>", "REPLACE_SHA")
    return "\n".join(
        [
            "apiVersion: networking.k8s.io/v1",
            "kind: Ingress",
            "metadata:",
            f"  name: {name}",
            f"  namespace: {service['namespace']}",
            "  annotations:",
            "    kubernetes.io/ingress.class: apisix",
            "    cert-manager.io/cluster-issuer: letsencrypt-prod",
            f"    external-dns.alpha.kubernetes.io/hostname: {hostname}",
            "spec:",
            "  tls:",
            f"    - hosts:",
            f"        - {hostname}",
            f"      secretName: {name}-tls",
            "  rules:",
            f"    - host: {hostname}",
            "      http:",
            "        paths:",
            "          - path: /",
            "            pathType: Prefix",
            "            backend:",
            "              service:",
            f"                name: {name}",
                "                port:",
            "                  number: 80",
        ]
    ) + "\n"


def render_shared_stunnel() -> dict[str, str]:
    configmap = "\n".join(
        [
            "apiVersion: v1",
            "kind: ConfigMap",
            "metadata:",
            "  name: stunnel-client-config",
            "  namespace: core-platform",
            "data:",
            "  stunnel.conf: |",
            "    foreground = yes",
            "    pid = /tmp/stunnel.pid",
            "    [postgres-client]",
            "    client = yes",
            "    accept = 0.0.0.0:15432",
            "    connect = postgresql.svc.plus:443",
            "    verify = 2",
            "    CAfile = /etc/ssl/certs/ca-certificates.crt",
            "    checkHost = postgresql.svc.plus",
        ]
    ) + "\n"
    deployment = "\n".join(
        [
            "apiVersion: apps/v1",
            "kind: Deployment",
            "metadata:",
            "  name: stunnel-client",
            "  namespace: core-platform",
            "spec:",
            "  replicas: 1",
            "  selector:",
            "    matchLabels:",
            "      app: stunnel-client",
            "  template:",
            "    metadata:",
            "      labels:",
            "        app: stunnel-client",
            "    spec:",
            "      containers:",
            "        - name: stunnel",
            "          image: dweomer/stunnel",
            "          command: [\"stunnel\", \"/etc/stunnel/stunnel.conf\"]",
            "          ports:",
            "            - containerPort: 15432",
            "          resources:",
            "            requests:",
            "              cpu: \"50m\"",
            "              memory: \"64Mi\"",
            "            limits:",
            "              cpu: \"100m\"",
            "              memory: \"128Mi\"",
            "          volumeMounts:",
            "            - name: config",
            "              mountPath: /etc/stunnel",
            "          readinessProbe:",
            "            tcpSocket:",
            "              port: 15432",
            "            initialDelaySeconds: 5",
            "            periodSeconds: 10",
            "      volumes:",
            "        - name: config",
            "          configMap:",
            "            name: stunnel-client-config",
        ]
    ) + "\n"
    service = "\n".join(
        [
            "apiVersion: v1",
            "kind: Service",
            "metadata:",
            "  name: stunnel-client",
            "  namespace: core-platform",
            "spec:",
            "  selector:",
            "    app: stunnel-client",
            "  ports:",
            "    - port: 15432",
            "      targetPort: 15432",
            "      protocol: TCP",
        ]
    ) + "\n"
    return {
        "configmap.yaml": configmap,
        "deployment.yaml": deployment,
        "service.yaml": service,
    }


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default=str(ROOT / "tmp" / "k3s-core"))
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    inventory = load_inventory()

    for service in inventory["services"]:
        desc_path = service.get("cloud_run_desc")
        desc = load_cloud_run_desc(ROOT / desc_path) if desc_path else None
        envs = env_items(service, desc)
        image = infer_image(service, desc)
        service_dir = output_dir / service["name"]

        write_file(service_dir / "secret.example.yaml", render_secret(service, envs))
        write_file(service_dir / "configmap.yaml", render_configmap(service, envs))
        write_file(service_dir / "deployment.yaml", render_deployment(service, image, envs))
        write_file(service_dir / "service.yaml", render_service(service, "stable"))
        write_file(service_dir / "ingress.yaml", render_ingress(service, "stable"))
        write_file(service_dir / "preview-deployment.yaml", render_preview_deployment(service, image))
        write_file(service_dir / "preview-service.yaml", render_service(service, "preview"))
        write_file(service_dir / "preview-ingress.yaml", render_ingress(service, "preview"))

    infra_dir = output_dir / "infra"
    for filename, content in render_shared_stunnel().items():
        write_file(infra_dir / filename, content)

    print(f"Rendered manifests to {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
