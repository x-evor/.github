#!/usr/bin/env python3
"""Estimate whether the core Cloud Run services fit on a 2C4G single-node K3s host."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = ROOT / "config" / "k3s-migration" / "core-services.json"


def load_inventory() -> dict:
    with INVENTORY_PATH.open() as f:
        return json.load(f)


def summarize(items: list[dict], prefix: str) -> tuple[int, int]:
    cpu = sum(int(item[f"{prefix}_cpu_m"]) for item in items)
    mem = sum(int(item[f"{prefix}_memory_mib"]) for item in items)
    return cpu, mem


def fmt_fit(value: int, capacity: int) -> str:
    pct = value / capacity * 100
    return f"{value} / {capacity} ({pct:.1f}%)"


def main() -> int:
    inventory = load_inventory()
    target = inventory["target_host"]
    infra = inventory["infrastructure"]
    services = inventory["services"]

    infra_req = summarize(infra, "request")
    infra_lim = summarize(infra, "limit")
    svc_req = summarize(services, "recommended_request")
    svc_lim = summarize(services, "recommended_limit")

    total_req = (infra_req[0] + svc_req[0], infra_req[1] + svc_req[1])
    total_lim = (infra_lim[0] + svc_lim[0], infra_lim[1] + svc_lim[1])
    cloud_run_mem = sum(int(s["cloud_run_limit_memory_mib"]) for s in services)
    cloud_run_cpu = sum(int(s["cloud_run_limit_cpu_m"]) for s in services)

    print("Target host")
    print(f"  name:   {target['name']}")
    print(f"  cpu:    {target['cpu_millicores']}m")
    print(f"  memory: {target['memory_mib']}Mi")
    print()

    print("Infrastructure budget")
    print(f"  request cpu: {infra_req[0]}m")
    print(f"  request mem: {infra_req[1]}Mi")
    print(f"  limit cpu:   {infra_lim[0]}m")
    print(f"  limit mem:   {infra_lim[1]}Mi")
    print()

    print("Core services budget")
    print(f"  request cpu: {svc_req[0]}m")
    print(f"  request mem: {svc_req[1]}Mi")
    print(f"  limit cpu:   {svc_lim[0]}m")
    print(f"  limit mem:   {svc_lim[1]}Mi")
    print()

    print("Combined fit on 2C4G")
    print(f"  request cpu: {fmt_fit(total_req[0], target['cpu_millicores'])}")
    print(f"  request mem: {fmt_fit(total_req[1], target['memory_mib'])}")
    print(f"  limit cpu:   {fmt_fit(total_lim[0], target['cpu_millicores'])}")
    print(f"  limit mem:   {fmt_fit(total_lim[1], target['memory_mib'])}")
    print()

    print("Current Cloud Run reference for these five services")
    print(f"  cloud run cpu limit sum: {cloud_run_cpu}m")
    print(f"  cloud run mem limit sum: {cloud_run_mem}Mi")
    print()

    print("Per-service recommendation")
    for svc in services:
        print(
            f"  - {svc['name']}: "
            f"req {svc['recommended_request_cpu_m']}m/{svc['recommended_request_memory_mib']}Mi, "
            f"limit {svc['recommended_limit_cpu_m']}m/{svc['recommended_limit_memory_mib']}Mi"
        )

    print()
    if total_req[1] < target["memory_mib"] and total_req[0] < target["cpu_millicores"]:
        print("Result")
        print("  Request budget fits on 2C4G.")
        if total_lim[1] >= target["memory_mib"] - 256:
            print("  Peak memory headroom is thin; keep one replica per service and avoid extra workloads.")
        else:
            print("  Peak memory still leaves some room, but watch APISIX and cert-manager during renewals.")
    else:
        print("Result")
        print("  Even the request budget does not fit; move to 4C8G before cutover.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
