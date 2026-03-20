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

Default GCP values in this repo:

- `gcp_project_id: xzerolab-480008`
- `zone: asia-east2-a` which maps to region `asia-east2` (Hong Kong)

## Local usage

```bash
bash scripts/cloud-dev-desktop/precheck-local.sh

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

For the cross-cloud desktop set requested in this repo, start from:

- `ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml`
- `ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml`
- `ansible/vars/cloud_dev_desktop.gcp.ubuntu-kde.example.yml`

The orchestration wrapper below reuses the checked-in `create.sh`,
`bootstrap.sh`, and `verify.sh` scripts, creates the Azure Windows machine
first, appends its public IP to the two GCP Linux allowlists, generates a
dedicated SSH key for the Windows-to-GCP hop, and then writes SSH aliases on
the Windows host for the two Linux desktops:

```bash
bash scripts/cloud-dev-desktop/create-cross-cloud-dev-machines.sh --dry-run

bash scripts/cloud-dev-desktop/create-cross-cloud-dev-machines.sh \
  --windows-request ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml \
  --fedora-request ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml \
  --kde-request ansible/vars/cloud_dev_desktop.gcp.ubuntu-kde.example.yml
```

## Shutdown and teardown modes

There are now two retirement modes for cloud dev desktops:

- `park`: lowest-consumption mode without deleting the VM
- `destroy`: delete the VM and remove the local state file

Provider behavior:

- Azure `park`: `az vm deallocate`
- GCP `park`: `gcloud compute instances stop`
- Azure/GCP `destroy`: delete the VM

Single machine examples:

```bash
bash scripts/cloud-dev-desktop/destroy.sh \
  --provider azure \
  --request ansible/vars/cloud_dev_desktop.azure.windows-desktop.example.yml \
  --mode park

bash scripts/cloud-dev-desktop/destroy.sh \
  --provider gcp \
  --request ansible/vars/cloud_dev_desktop.gcp.fedora-gnome.example.yml \
  --mode destroy
```

Fleet examples:

```bash
bash scripts/cloud-dev-desktop/teardown-cross-cloud-dev-machines.sh --mode park

bash scripts/cloud-dev-desktop/teardown-cross-cloud-dev-machines.sh --mode destroy
```

Recommended usage:

- Use `park` when you want to keep the machine and its disk contents for later reuse.
- Use `destroy` when the environment is no longer needed and should be fully removed.

State files are written under `.ansible/cloud-dev-desktop/` and are used to
carry connection details between lifecycle stages.

If `ssh_public_key_path` is omitted for Linux hosts, the control plane defaults
to `~/.ssh/id_rsa.pub` so later Ansible SSH access can reuse the same key pair.

## CI usage

Use `.github/workflows/cloud-dev-desktop.yml`.

The workflow keeps orchestration in YAML and defers operational logic to the
checked-in wrapper scripts.

## Pre Role: Cloud CLI Prereqs

For hosts that need local cloud tooling before other automation, use:

- `ansible/playbooks/install_cloud_cli_prereqs.yml`
- `ansible/roles/cloud_cli_prereqs/`

This pre role installs:

- macOS: `azure-cli`, `google-cloud-sdk`
- Windows: `Microsoft.AzureCLI`, `Google.CloudSDK`
- Linux: `az`, `gcloud`

Example:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/install_cloud_cli_prereqs.yml
```

The same cloud CLI installation is also embedded into the platform roles:

- `ansible/roles/dev_desktop_macos_local/`
- `ansible/roles/dev_desktop_windows_local/`
- `ansible/roles/dev_desktop_linux_local/`
- `ansible/roles/dev_desktop_windows/`
- `ansible/roles/dev_desktop_fedora_gnome/`
- `ansible/roles/dev_desktop_debian_kde/`

For local workstation initialization:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i "localhost," \
  -c local \
  ansible/playbooks/init_macos_local_dev.yml

ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i "localhost," \
  -c local \
  ansible/playbooks/init_linux_local_dev.yml
```

For Windows local machines, run:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i inventory.ini \
  ansible/playbooks/init_windows_local_dev.yml
```

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
