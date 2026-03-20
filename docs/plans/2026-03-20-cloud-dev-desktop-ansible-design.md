# Cloud Dev Desktop Ansible Design

## Summary

This document defines the first implementation of a multi-cloud desktop VM
control plane inside the control repo. The design uses provider lifecycle
playbooks for Azure and GCP, OS-specific bootstrap roles, wrapper scripts for
local and CI execution, and state files under `.ansible/cloud-dev-desktop/`.

## Lifecycle

1. `create`: create network + VM + access rules and persist state
2. `bootstrap`: connect to the created VM and install desktop/toolchains
3. `verify`: run profile-specific validation commands
4. `destroy`: delete the VM and created access resources
5. `cleanup-expired`: enumerate tagged resources and remove expired temporary VMs

## Profile matrix

- `windows`: Windows 10/11 amd64 with RDP, Codex, Android Studio, VS Code
- `fedora-gnome`: Fedora 43 GNOME with GTK-oriented Flutter/Dart build deps
- `debian-kde`: Debian 13 or Ubuntu-family KDE with Qt-oriented Flutter/Dart build deps

## Security defaults

- CLI auth is the default local execution path
- Public ingress requires a non-empty `allowed_cidrs`
- Resource cleanup is scoped by `managed_by=ansible` and `toolkit_scope=cloud-dev-desktop`
- Real secrets stay outside Git; `.env.example` documents only keys

## Known v1 limits

- Windows automation assumes remote management can be reached after provisioning
- Azure/GCP image identifiers are overrideable because marketplace image names drift
- Linux remote desktop enablement is profile-specific and may still need image tuning per distro release
