# Cloud Dev Desktop Control Plane

This control-plane slice provisions, bootstraps, verifies, and destroys temporary
desktop VMs for development and testing on Azure and GCP.

## Supported profiles

- Windows 10/11 amd64 with `Codex CLI/App`, `Node.js 22+`, `Android Studio`, `VS Code`, `OpenSSH Server`, and `Flutter SDK`
- Fedora 43 GNOME amd64 with `Codex CLI`, `Node.js 22+`, latest stable Go from `go.dev`, GTK desktop app development packages, and `Flutter SDK`
- Debian 13 / Ubuntu family KDE amd64 with `Codex CLI`, `Node.js 22+`, latest stable Go from `go.dev`, Qt desktop app development packages, and `Flutter SDK`

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
- `zone: asia-northeast1-a` which maps to region `asia-northeast1` (Tokyo)

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

## Parity Release Workflow

For a large-version parity release that uses the three cloud desktops as
dedicated validation hosts, use:

- `.github/workflows/cloud-dev-desktop-parity-release.yml`
- `scripts/cloud-dev-desktop/parity-release.sh`
- `scripts/cloud-dev-desktop/render-parity-release-brief.py`
- `scripts/cloud-dev-desktop/prepare-parity-worktree.sh`
- `ansible/vars/cloud_dev_desktop.parity_release.example.yml`

Supported wrapper actions:

- `provision`
  - Calls `create-cross-cloud-dev-machines.sh`
  - Creates the Azure Windows host first, then the two GCP Linux hosts
  - Reuses the existing Ansible-backed `create/bootstrap/verify` wrappers
  - Refreshes `.ansible/cloud-dev-desktop/runtime/parity-release-brief.md` after host provisioning
- `brief`
  - Renders a Markdown dispatch brief for `~/.codex/skills/architect-orchestrator/`
  - Includes current host readiness from `.ansible/cloud-dev-desktop/*.json`
- `status`
  - Re-renders the current parity release host/task matrix without changing infrastructure
- `park`
  - Calls `teardown-cross-cloud-dev-machines.sh --mode park`
  - Stops/deallocates hosts without deleting them
- `destroy`
  - Calls `teardown-cross-cloud-dev-machines.sh --mode destroy`
  - Deletes the hosts and removes their local state files

Local usage:

```bash
bash scripts/cloud-dev-desktop/parity-release.sh \
  --action provision \
  --windows-request .ansible/cloud-dev-desktop/runtime/windows-real.yml \
  --fedora-request .ansible/cloud-dev-desktop/runtime/fedora-real.yml \
  --kde-request .ansible/cloud-dev-desktop/runtime/kde-real.yml

bash scripts/cloud-dev-desktop/parity-release.sh \
  --action brief \
  --manifest ansible/vars/cloud_dev_desktop.parity_release.example.yml

bash scripts/cloud-dev-desktop/parity-release.sh \
  --action park \
  --windows-request .ansible/cloud-dev-desktop/runtime/windows-real.yml \
  --fedora-request .ansible/cloud-dev-desktop/runtime/fedora-real.yml \
  --kde-request .ansible/cloud-dev-desktop/runtime/kde-real.yml
```

The generated brief is written to:

- `.ansible/cloud-dev-desktop/runtime/parity-release-brief.md`

This file is local runtime state and should not be committed.

`provision` refreshes this brief automatically so the next step can hand the
artifact directly to `architect-orchestrator` without a separate render pass.
In `--dry-run`, the brief reflects whatever real state files already exist; it
does not synthesize ready Linux hosts from Ansible check-mode output.

The generated brief now includes:

- host inventory from `.ansible/cloud-dev-desktop/*.json`
- branch-to-host lane mapping
- macOS/iOS protection constraints
- host-side `git worktree` preparation commands

To prepare a parity worktree on the assigned host, use:

```bash
bash scripts/cloud-dev-desktop/prepare-parity-worktree.sh \
  --repo /workspace/xworkmate.svc.plus \
  --branch codex/windows-parity \
  --base-ref origin/main \
  --worktree /workspace/xworkmate.svc.plus-windows-parity
```

The helper always starts the parity worktree from `origin/main`. Existing
remote `codex/*-parity` branches are treated as publish targets for this run,
not as the starting baseline.

The parity release manifest maps the four default lanes:

- `codex/windows-parity` on the Azure Windows host
- `codex/android-mobile-parity` on the Azure Windows host
- `codex/linux-gnome-desktop-parity` on the Fedora GNOME host
- `codex/linux-kde-desktop-parity` on the Ubuntu KDE host

Default host-side evidence for those lanes is:

- Windows desktop: `flutter build windows` plus a local app launch/smoke check
- Android from Windows: successful `flutter build apk`
- Fedora GNOME: desktop build plus a local app launch/smoke check
- Ubuntu KDE: desktop build plus a local app launch/smoke check

Android emulator and `adb` runtime validation are intentionally handled on the
local macOS workstation. The Azure Windows host is only required to prove that
the Android target still packages successfully.

The host-side worktree helper is:

```bash
bash scripts/cloud-dev-desktop/prepare-parity-worktree.sh \
  --repo /path/to/xworkmate.svc.plus \
  --branch codex/windows-parity \
  --worktree /path/to/xworkmate.svc.plus-windows-parity \
  --dry-run
```

Operational split:

- GitHub Actions + Ansible manage fleet lifecycle and brief/status generation.
- `architect-orchestrator` plus helper scripts manage the host-level worktrees and debugging lanes.

### Known Gaps

- Azure Windows Android parity is currently accepted on a packaging-only gate:
  `flutter build apk`.
- Android emulator and `adb` runtime validation moved to the local macOS
  workstation.
- Local macOS Android validation is only partially complete:
  - AVD `codex-api36` has been created.
  - `adb devices` reaches `emulator-5554 device`.
  - `flutter run -d emulator-5554 --debug` is still incomplete because Gradle
    dependency downloads are unstable on the current network path.
- The following macOS device-run integration checks remain manual follow-up and
  must not be reported as automated pass:
  - `flutter test integration_test/desktop_navigation_flow_test.dart -d macos`
  - `flutter test integration_test/desktop_settings_flow_test.dart -d macos`

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
- The parity release wrapper is infrastructure orchestration plus dispatch-brief
  generation. It does not yet auto-drive the remote worktrees itself.
