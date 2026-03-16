# Service Release Control Plane Workflow

Workflow file:

- `.github/workflows/service_release_control_plane.yml`

This workflow is the control-plane entrypoint for the Cloud Run-like `svc.plus` release system.

It now supports:

- `workflow_dispatch` for manual runs from the control repo
- `workflow_call` for thin wrapper workflows in each service repo

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

Each sub repo still owns:

- its own Dockerfile
- its own Ansible playbook path
- its own runtime env shape
- service-specific entrypoint/bootstrap behavior

This keeps service implementation details inside each service repository.

## Source Of Truth

The workflow resolves metadata from:

- `console.svc.plus.code-workspace`
- `config/single-node-release/repositories.json`
- `config/single-node-release/services.json`

That metadata replaces hardcoded service definitions in the workflow logic.

## Inputs

### `workflow_dispatch`

- `service`
  - Logical service key from `config/single-node-release/services.json`
  - Example: `accounts`
- `track`
  - One of: `prod`, `preview`
- `service_ref`
  - Branch, tag, or commit SHA of the service repository
- `run_apply`
  - `false`: stop after stage 3
  - `true`: continue to stage 4

CLI example:

```bash
gh workflow run service_release_control_plane.yml \
  -f service=accounts \
  -f track=prod \
  -f service_ref=release/2026-03-16 \
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
- checkout the target service repo
- build the service image
- push to `ghcr.io`
- compute the immutable release domain

### Stage 2. Update Release DNS

- create or update the release-domain CNAME in Cloudflare
- target the single deploy host alias from `ansible/inventory.ini`

This stage only handles the immutable release domain.
Stable domains should already point to the deploy host and should not be switched per release.

### Stage 3. Ansible Dry Run

- prepare SSH credentials on the runner
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

It does not require moving service runtime ownership out of the service repos.

## Required GitHub Secrets

Sensitive values belong in GitHub Secrets, ideally at org scope if multiple repos will call this workflow.

| Secret | Purpose |
| --- | --- |
| `GHCR_USERNAME` | GHCR login username |
| `GHCR_TOKEN` | GHCR package push/pull |
| `CLOUDFLARE_DNS_API_TOKEN` | immutable release DNS management |
| `WORKSPACE_REPO_TOKEN` | checkout sibling private repos when needed |
| `SINGLE_NODE_VPS_SSH_PRIVATE_KEY` | SSH key for Ansible CD stages |
| `ACCOUNTS_ANSIBLE_VARS_YAML` | `accounts` secret runtime vars |
| `RAG_SERVER_ANSIBLE_VARS_YAML` | `rag-server` secret runtime vars |
| `X_CLOUD_FLOW_ANSIBLE_VARS_YAML` | `x-cloud-flow` secret runtime vars |
| `X_OPS_AGENT_ANSIBLE_VARS_YAML` | `x-ops-agent` secret runtime vars |
| `X_SCOPE_HUB_ANSIBLE_VARS_YAML` | `x-scope-hub` secret runtime vars |

## Required GitHub Variables

Non-sensitive infrastructure values belong in GitHub Variables or checked-in catalogs.

| Variable | Purpose |
| --- | --- |
| `SINGLE_NODE_VPS_SSH_HOST` | SSH target IP |
| `SINGLE_NODE_VPS_SSH_USER` | SSH target user |
| `SINGLE_NODE_VPS_SSH_PORT` | SSH target port |
| `SINGLE_NODE_VPS_SSH_KNOWN_HOSTS` | host key pinning |

These checked-in values are not GitHub Variables:

- repo URL
- repo category
- stable domains
- release prefixes
- host ports
- Dockerfile/build paths

Those live in `config/single-node-release/*.json`.

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
    uses: cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/.github/workflows/service_release_control_plane.yml@main
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
    uses: cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/.github/workflows/service_release_control_plane.yml@main
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
