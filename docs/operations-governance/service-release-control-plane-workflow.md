# Service Release Control Plane Workflow

Workflow file:

- `.github/workflows/service_release_apiserver-deploy.yml`
- `.github/workflows/stable_release_gate.yml`

This workflow is the control-plane entrypoint for the Cloud Run-like `svc.plus` release system.

It now supports:

- `workflow_dispatch` for manual runs from the control repo
- `workflow_call` for thin wrapper workflows in each service repo

The companion stable release gate workflow supports:

- `workflow_dispatch` for `local` and `stable` validation modes
- `workflow_call` from the release deploy workflow after apply

Current runtime profile:

- `single-node-docker-compose`

Planned runtime profiles:

- `single-node-k3s`
- `cluster-k8s`

## Control-Plane Boundary

The control repo owns:

- repository discovery from `console.svc.plus.code-workspace`
- repo and service catalogs under `config/single-node-release/`
- GitHub Actions orchestration
- immutable release DNS creation
- Ansible SSH bootstrap and runtime variable injection

Each service repo still owns:

- its own Dockerfile
- its own Ansible playbook path
- its own runtime env shape
- service-specific entrypoint/bootstrap behavior

This keeps service implementation details inside each service repository.

## Source Of Truth

The workflow resolves metadata from:

- `console.svc.plus.code-workspace`
- `config/single-node-release/repositories.json`
- `config/single-node-release/services/common.yaml`
- `config/single-node-release/services/<track>-<service>.yaml`

That metadata replaces hardcoded service definitions in the workflow logic.

Catalog split:

- `common.yaml` stores shared service metadata such as repo, playbook, Docker, and secret mapping
- `<track>-<service>.yaml` stores track-specific release settings such as stable domain, release prefix, and host port

Optional service-level host targeting:

- `common.yaml` may set `deploy_server_alias` for services that should not use the default release host alias
- if omitted, the resolver still falls back to the first alias from `ansible/inventory.ini`

## Inputs

### `workflow_dispatch`

- `service`
  - Logical service key from `config/single-node-release/services/common.yaml`
  - Example: `accounts`
- `track`
  - One of: `prod`, `preview`
- `service_ref`
  - Branch, tag, or commit SHA of the service repository
  - For `prod`, refs under `release/*` also become part of the immutable release-domain name
- `run_apply`
  - `false`: stop after stage 3
  - `true`: continue to stage 4
- `ssh_host`
  - Optional override for the default SSH target host
- `ssh_user`
  - Optional override for the default SSH target user
- `ssh_port`
  - Optional override for the default SSH target port
- `ssh_known_hosts`
  - Optional override for the runner-side `known_hosts` payload

For release-enabled repositories, `service_ref` is the source revision used for the service checkout.

CLI example:

```bash
gh workflow run service_release_apiserver-deploy.yml \
  -f service=accounts \
  -f track=prod \
  -f service_ref=release/2026-03-16 \
  -f ssh_host=5.78.45.49 \
  -f ssh_user=root \
  -f ssh_port=22 \
  -f run_apply=false
```

### `workflow_call`

Recommended service-repo wrappers:

- `push` to `release/*` -> call with `track=prod`
- `pull_request` targeting `main` -> call with `track=preview`

The caller repo should pass:

- `service`
- `track`
- `service_ref`
- `run_apply`

## Stage Model

### Stage 1. Build And Push Image

- resolve repo/service metadata from workspace + catalogs
- checkout the target service repo from the sibling repository workspace
- build the service image
- push to `ghcr.io`
- compute the immutable release domain
  - prod + `release/*`: `<release-prefix>-<deploy-hostname>-<release-name>-<git-short-commit>.<domain>`
  - preview or non-`release/*`: `<release-prefix>-<deploy-hostname>-<git-short-commit>.<domain>`

### Stage 2. Update Release DNS

- create or update the release-domain CNAME in Cloudflare
- target the single deploy host alias from `ansible/inventory.ini`

This stage only handles the immutable release domain.
Stable domains should already point to the deploy host and should not be switched per release.

### Stage 3. Ansible Dry Run

- write the deploy private key to the runner at `~/.ssh/id_rsa`
- render a temporary runtime inventory from `ansible/inventory.ini.tmpl`
- materialize:
  - service secret vars from GitHub Secrets
  - runtime vars from the control-plane catalog
- checkout the service repo
- run the service repo playbook with:
  - `ansible-playbook -D -C`

### Stage 4. Ansible Apply

- same runtime shape as stage 3
- run the service repo playbook with:
  - `ansible-playbook -D`

### Stage 5. Stable Release Gate

- call `.github/workflows/stable_release_gate.yml`
- `mode=local` validates repo-local docs and metadata wiring without network access
- `mode=stable` adds a live smoke against the resolved stable domain and healthcheck path
- this gate runs after stage 4 when `run_apply=true`

## Current Release Flow Shape

The first version keeps the already-working deployment runtime:

- `docker compose`
- Caddy reverse proxy
- per-service playbooks in the sub repos

This means the Cloud Run-like behavior is implemented at the release-control layer:

- immutable release domains
- fixed stable domains
- fixed prod/preview ports
- active revision recorded by the release process
- local and stable gate modes are enforced before stable sign-off

It does not require moving service runtime ownership out of the service repos.

## Required GitHub Secrets

Sensitive values belong in GitHub Secrets, ideally at org scope if multiple repos will call this workflow.

| Secret | Purpose |
| --- | --- |
| `GHCR_TOKEN` | GHCR package push/pull |
| `CLOUDFLARE_DNS_API_TOKEN` | immutable release DNS management |
| `WORKSPACE_REPO_TOKEN` | checkout sibling private repos when needed |
| `SINGLE_NODE_VPS_SSH_PRIVATE_KEY` | SSH key for Ansible CD stages |
| `INTERNAL_SERVICE_TOKEN` | shared internal auth token used by `accounts` |
| `ACCOUNTS_DB_PASSWORD` | `accounts` database password, shared for `POSTGRES_PASSWORD` and `DB_PASSWORD` |
| `ACCOUNTS_SMTP_PASSWORD` | `accounts` SMTP password |
| `RAG_SERVER_ANSIBLE_VARS_YAML` | `rag-server` secret runtime vars |
| `X_CLOUD_FLOW_ANSIBLE_VARS_YAML` | `x-cloud-flow` secret runtime vars |
| `X_OPS_AGENT_ANSIBLE_VARS_YAML` | `x-ops-agent` secret runtime vars |
| `X_SCOPE_HUB_ANSIBLE_VARS_YAML` | `x-scope-hub` secret runtime vars |

## Built-In SSH Defaults

The control-plane workflow now carries the default single-node SSH target directly in the checked-in workflow file.

| Key | Default |
| --- | --- |
| `SINGLE_NODE_VPS_SSH_HOST` | `5.78.45.49` |
| `SINGLE_NODE_VPS_SSH_USER` | `root` |
| `SINGLE_NODE_VPS_SSH_PORT` | `22` |
| `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS` | empty |

Manual `workflow_dispatch` runs can override those values with `ssh_host`, `ssh_user`, `ssh_port`, and `ssh_known_hosts`.

For deploy-key preparation and rotation, see [pre-github-deploy-key.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/operations-governance/pre-github-deploy-key.md).

These checked-in values are not GitHub Variables:

- `GHCR_USERNAME` is defined in the workflow env and currently set to `svc-design`

- repo URL
- repo category
- stable domains
- release prefixes
- host ports
- Dockerfile/build paths

Those live in `config/single-node-release/repositories.json` and `config/single-node-release/services/*.yaml`.

For `accounts.svc.plus`, non-sensitive release defaults are checked in with the service repo's release vars. GitHub Secrets only carry `INTERNAL_SERVICE_TOKEN`, the shared database password, and the SMTP password.

## Example Service-Repo Wrapper

Minimal release wrapper in a service repo:

```yaml
name: Prod Track

on:
  push:
    branches:
      - "release/**"

jobs:
  prod:
    uses: cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/.github/workflows/service_release_apiserver-deploy.yml@main
    with:
      service: accounts
      track: prod
      service_ref: ${{ github.sha }}
      run_apply: true
    secrets: inherit
```

Minimal preview wrapper:

```yaml
name: Preview Track

on:
  pull_request:
    branches:
      - main
    types:
      - opened
      - synchronize
      - reopened

jobs:
  preview:
    uses: cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/.github/workflows/service_release_apiserver-deploy.yml@main
    with:
      service: accounts
      track: preview
      service_ref: ${{ github.event.pull_request.head.sha }}
      run_apply: true
    secrets: inherit
```

## Operational Notes

- `accounts` prod and preview still use the same sub-repo playbook.
- `track` changes the stable domain, release prefix, and host port.
- The workflow no longer treats preview as a separate hardcoded pseudo-service.
- Stable domains should be pointed once to the deploy host; only release domains are mutated in CI.
