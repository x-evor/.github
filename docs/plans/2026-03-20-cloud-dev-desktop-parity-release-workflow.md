# Cloud Dev Desktop Parity Release Workflow

## Goal

Standardize the large-version parity release flow for `xworkmate.svc.plus`
across:

- Azure Windows host
- GCP Fedora GNOME host
- GCP Ubuntu KDE host

The workflow keeps cloud lifecycle under Ansible/wrapper control and turns
remote branch validation into a repeatable operator playbook for
`~/.codex/skills/architect-orchestrator/`.

## Workflow Layers

### 1. Infrastructure Layer

Use:

- `scripts/cloud-dev-desktop/create-cross-cloud-dev-machines.sh`
- `scripts/cloud-dev-desktop/teardown-cross-cloud-dev-machines.sh`
- `scripts/cloud-dev-desktop/parity-release.sh`

These wrappers remain the canonical lifecycle entrypoints for:

- `provision`
- `brief`
- `status`
- `park`
- `destroy`

`provision` is the handoff point from infrastructure to dispatch. After the
hosts are created, bootstrapped, and verified, it also refreshes the parity
brief so the next step can immediately hand the artifact to
`architect-orchestrator`.

### 2. Dispatch Layer

Use:

- `ansible/vars/cloud_dev_desktop.parity_release.example.yml`
- `scripts/cloud-dev-desktop/render-parity-release-brief.py`
- `scripts/cloud-dev-desktop/prepare-parity-worktree.sh`

The manifest defines:

- host-to-provider mapping
- request file mapping
- branch/worktree mapping
- validation focus per parity lane
- `origin/main` as the reset baseline for each parity lane

The brief renderer produces a compact Markdown handoff for
`architect-orchestrator`, including current host state from
`.ansible/cloud-dev-desktop/*.json`.

The worktree helper keeps each parity lane on its own branch/path pair once the
assigned host is ready.

It also emits standard `git worktree` preparation commands through
`scripts/cloud-dev-desktop/prepare-parity-worktree.sh`.

### 3. CI Layer

Use:

- `.github/workflows/cloud-dev-desktop-parity-release.yml`

This workflow drives the wrapper from `workflow_dispatch` and supports:

- `provision`
- `brief`
- `status`
- `park`
- `destroy`

The pipeline owns infrastructure lifecycle only. Host-level checkout,
worktree creation, debugging, validation, and parity-branch pushes are driven
through the generated brief plus `architect-orchestrator`.

For `provision`, `brief`, and `status`, the workflow uploads the rendered
dispatch brief as a workflow artifact.

## Intended Branch Topology

- Windows desktop parity: `codex/windows-parity`
- Android parity from Windows host: `codex/android-mobile-parity`
- Fedora GNOME parity: `codex/linux-gnome-desktop-parity`
- Ubuntu KDE parity: `codex/linux-kde-desktop-parity`

## Host-Side Validation Baseline

- Windows desktop parity: `flutter build windows` plus a Windows app launch/smoke check
- Android parity from the Windows host: successful `flutter build apk`
- Fedora GNOME parity: desktop build plus a local launch/smoke check
- Ubuntu KDE parity: desktop build plus a local launch/smoke check

Android emulator and `adb` runtime validation are owned by the local macOS
workstation. They are not part of the Azure Windows parity gate.

## Post-Run Policy

Default release-close behavior is:

- push validated parity branches
- `park` all three hosts
- do not delete the machines unless explicitly requested

## Operator Sequence

1. Run `parity-release.sh --action provision` locally or via GitHub Actions.
2. Run `parity-release.sh --action brief` and open the generated brief.
3. Use `~/.codex/skills/architect-orchestrator/` with that brief to dispatch the four parity lanes.
4. On each assigned host, prepare the lane worktree with `prepare-parity-worktree.sh`.
5. Capture build/run evidence, push only the assigned parity branch, then park the fleet.

## Manual Follow-Up

- Azure Windows Android validation is packaging-only for the current release
  close-out: `flutter build apk`.
- Android emulator and `adb` runtime validation now live on the local macOS
  workstation.
- Current local macOS Android status:
  - AVD `codex-api36` exists.
  - `adb devices` reaches `emulator-5554 device`.
  - `flutter run -d emulator-5554 --debug` is still incomplete because Gradle
    dependency downloads are unstable.
- The following macOS device-run integration tests are still manual follow-up:
  - `integration_test/desktop_navigation_flow_test.dart -d macos`
  - `integration_test/desktop_settings_flow_test.dart -d macos`
