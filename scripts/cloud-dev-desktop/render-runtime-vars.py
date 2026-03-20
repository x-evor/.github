#!/usr/bin/env python3
import argparse
import json
import os
from copy import deepcopy
from pathlib import Path

import yaml


def deep_merge(left, right):
    result = deepcopy(left)
    for key, value in (right or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_yaml(path):
    with open(path, "r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def main():
    parser = argparse.ArgumentParser(description="Render runtime vars and inventory for cloud dev desktop playbooks.")
    parser.add_argument("--request", required=True)
    parser.add_argument("--provider-defaults", required=True)
    parser.add_argument("--runtime-vars-out", required=True)
    parser.add_argument("--inventory-out", required=True)
    parser.add_argument("--state-file")
    parser.add_argument("--allow-missing-ip", action="store_true")
    parser.add_argument("--provider-override")
    args = parser.parse_args()

    request = load_yaml(args.request)
    defaults = load_yaml(args.provider_defaults)
    merged = deep_merge(defaults, request)
    if args.provider_override:
        merged["provider"] = args.provider_override

    state = {}
    if args.state_file and Path(args.state_file).exists():
      with open(args.state_file, "r", encoding="utf-8") as handle:
        state = json.load(handle)
    merged = deep_merge(merged, state)

    provider = merged.get("provider")
    os_family = merged.get("os_family")
    if provider not in {"azure", "gcp"}:
        raise SystemExit("provider must be azure or gcp")
    if os_family not in {"windows", "fedora-gnome", "debian-kde"}:
        raise SystemExit("os_family must be windows, fedora-gnome, or debian-kde")

    runtime_dir = Path(args.runtime_vars_out).resolve().parent
    runtime_dir.mkdir(parents=True, exist_ok=True)

    merged.setdefault("toolchains", {})
    merged.setdefault("desktop_access", {})
    merged.setdefault("tags", {})
    merged["cloud_vm_state_file"] = args.state_file or merged.get("cloud_vm_state_file", "")
    merged["cloud_vm_state_root"] = str(Path(args.state_file).resolve().parent) if args.state_file else ""

    public_ip = merged.get("public_ip") or merged.get("cloud_vm_public_ip") or ""
    if not public_ip and not args.allow_missing_ip:
        raise SystemExit("missing public_ip/cloud_vm_public_ip; create first or pass --allow-missing-ip")

    with open(args.runtime_vars_out, "w", encoding="utf-8") as handle:
        json.dump(merged, handle, indent=2, sort_keys=True)
        handle.write("\n")

    inventory_lines = ["[cloud_desktop]"]
    if public_ip:
        hostvars = [
            f"{merged['profile_name']} ansible_host={public_ip}",
            f"ansible_user={state.get('admin_username', merged.get('admin_username', 'devadmin'))}",
        ]
        if os_family == "windows":
            win_password = os.environ.get("CLOUD_DEV_DESKTOP_WINDOWS_PASSWORD", "")
            hostvars.extend(
                [
                    "ansible_connection=winrm",
                    "ansible_port=5985",
                    "ansible_winrm_transport=basic",
                    "ansible_winrm_server_cert_validation=ignore",
                ]
            )
            if win_password:
                hostvars.append(f"ansible_password={win_password}")
        else:
            ssh_key = os.path.expanduser(merged.get("ssh_public_key_path", "~/.ssh/id_rsa.pub")).replace(".pub", "")
            hostvars.extend(
                [
                    "ansible_connection=ssh",
                    "ansible_port=22",
                    f"ansible_ssh_private_key_file={ssh_key}",
                ]
            )
        inventory_lines.append(" ".join(hostvars))

    inventory_lines.extend(
        [
            "",
            "[cloud_desktop:vars]",
            "ansible_python_interpreter=/usr/bin/python3",
        ]
    )
    with open(args.inventory_out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(inventory_lines) + "\n")


if __name__ == "__main__":
    main()
