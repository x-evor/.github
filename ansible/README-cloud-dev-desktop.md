# Cloud Dev Desktop Control Plane

This control-plane slice provisions, bootstraps, verifies, and destroys temporary
desktop VMs for development and testing on Azure and GCP.

## Supported profiles

- Windows 10/11 amd64 with `Codex + Android Studio + VS Code`
- Fedora 43 GNOME amd64 for Flutter/Dart GTK desktop builds
- Debian 13 / Ubuntu family KDE amd64 for Flutter/Dart Qt desktop builds

## Request contract

Primary input is a single YAML file. Start from:

- `ansible/vars/cloud_dev_desktop.request.example.yml`
- `ansible/vars/cloud_dev_desktop.azure.example.yml`
- `ansible/vars/cloud_dev_desktop.gcp.example.yml`

Required fields:

- `provider`
- `profile_name`
- `os_family`
- `admin_username`
- `allowed_cidrs`
- `ttl_hours`
- `owner`
- `purpose`

Common optional fields:

- `vm_size`
- `disk_gb`
- `ssh_public_key_path` (defaults to `~/.ssh/id_rsa.pub` for Linux profiles)
- `toolchains`
- `desktop_access`
- `tags`

Provider-specific fields:

- Azure: `region`, optional `image_offer`, `image_sku`, `azure_subscription_id`
- GCP: `zone`, optional `image_family`, `gcp_project_id`

## Local usage

```bash
bash scripts/cloud-dev-desktop/create.sh \
  --provider azure \
  --request ansible/vars/cloud_dev_desktop.request.example.yml \
  --dry-run

bash scripts/cloud-dev-desktop/bootstrap.sh \
  --provider azure \
  --request ansible/vars/cloud_dev_desktop.request.example.yml \
  --dry-run

bash scripts/cloud-dev-desktop/verify.sh \
  --provider azure \
  --request ansible/vars/cloud_dev_desktop.request.example.yml \
  --dry-run

bash scripts/cloud-dev-desktop/destroy.sh \
  --provider azure \
  --request ansible/vars/cloud_dev_desktop.request.example.yml \
  --dry-run
```

State files are written under `.ansible/cloud-dev-desktop/` and are used to
carry connection details between lifecycle stages.

If `ssh_public_key_path` is omitted for Linux hosts, the control plane defaults
to `~/.ssh/id_rsa.pub` so later Ansible SSH access can reuse the same key pair.

## CI usage

Use `.github/workflows/cloud-dev-desktop.yml`.

The workflow keeps orchestration in YAML and defers operational logic to the
checked-in wrapper scripts.

Recommended secrets/vars:

- `AZURE_SUBSCRIPTION_ID`
- `AZURE_CREDENTIALS_JSON`
- `AZURE_WINDOWS_ADMIN_PASSWORD`
- `GCP_PROJECT_ID`
- `GCP_SERVICE_ACCOUNT_JSON`
- `GCP_WINDOWS_ADMIN_PASSWORD`
- `CLOUD_DEV_DESKTOP_WINDOWS_PASSWORD`

## Notes

- Default auth model is local CLI session or CI service identity.
- Public-IP direct access is supported, but `allowed_cidrs` is mandatory.
- Cleanup only targets resources labeled/tagged with `managed_by=ansible` and
  `toolkit_scope=cloud-dev-desktop`.
