# OpenClaw Multi-Gateway Architecture

This document describes the recommended multi-gateway topology for a personal OpenClaw assistant that must remain reachable at all times while still preserving strong interactive capabilities on a local macOS node.

## Goals

- Keep one always-online remote entrypoint.
- Preserve strong interactive browser tasks on the local macOS node.
- Allow multiple gateway nodes to exist without sharing the same `openclaw.json`.
- Share long-lived memory and artifacts across nodes without sharing the full hot runtime state.
- Centralize auth, secrets, rate limiting, and upstream AI API access behind Kong.

## Architecture Principles

- Share one remote Git repository for cross-gateway code exchange, but keep one local clone and one live working tree per gateway.
- Do not synchronize full hot runtime state across gateways. `OPENCLAW_STATE_DIR`, browser state, locks, caches, and live workspace mutations stay node-local.
- Synchronize shared semantic memory through `MemOS`, not through Git or object storage.
- Use `MemOS-Cloud-OpenClaw-Plugin` as the lifecycle integration layer on each gateway: recall memory before execution, write memory back after execution.
- Use `GCS` / `S3` / `OSS` for attachments, snapshots, exports, and recovery payloads, not as the primary semantic memory store.
- When multiple Windows / macOS / Linux clients need one shared POSIX mount, prefer `JuiceFS` with self-hosted `PostgreSQL` metadata plus `GCS` object storage instead of direct `gcsfuse` or `rclone` bucket mounts.
- Keep `Kong` as the unified ingress and control plane for auth, rate limits, routing, provider governance, and optional presigned URL issuance.

In short:

- `Git` = code and workspace sync
- `MemOS` = semantic memory sync
- `JuiceFS` = shared POSIX mount
- object storage = artifact sync
- `Kong` = ingress and control plane

## Domains and Node Roles

| Domain | Node Role | Primary Purpose |
| :----- | :-------- | :-------------- |
| `openclaw.svc.plus` | Kong | Unified remote entrypoint, auth, token/API governance, upstream routing |
| `openclaw-local.svc.plus` | Local macOS Gateway | Strong interactive tasks, browser sessions, desktop-local tools |
| `openclaw-remote.svc.plus` | VPS Remote Gateway | Default 24x7 remote gateway, message ingress, non-interactive online tasks |
| `openclaw-cloud-run.svc.plus` | Cloud Run Gateway | Elastic overflow and failover for non-interactive online tasks |

## Responsibility Split

### Kong

Kong remains in the design because it reduces glue code for:

- token/API brokering
- AI Gateway plugin based upstream routing
- Vault backed secret injection
- auth and rate limiting
- consistent remote entrypoint
- VPS to Cloud Run failover

Kong should **not** become the scheduler for local-vs-remote execution or the owner of session state.

For a concrete route and upstream sketch, see [Kong Routing Draft](/kong-routing).

## Gateway-to-Model Contract

Each OpenClaw gateway should talk to Kong's AI Gateway layer rather than carrying a full set of upstream provider credentials locally.

- gateway nodes call the Kong provider proxy such as `llm.openclaw.svc.plus`
- gateway nodes request logical model routes or provider paths, not raw upstream secrets
- Kong plus AI Gateway plus Vault own provider token injection, model routing, and provider-specific headers
- local, VPS, and Cloud Run nodes can share the same logical provider contract while still keeping different node-local `openclaw.json` files

### Local macOS Gateway

The local macOS gateway is the only node that should handle strong interactive tasks:

- browser login sessions
- desktop-local automation
- tasks that require a local browser profile
- tasks that need low latency user interaction

It should stay local-first by default. Do not make `/opt/data` the default hot runtime state for `openclaw-local.svc.plus`.

### VPS Remote Gateway

The VPS node is the default remote gateway:

- always online
- receives remote traffic from `openclaw.svc.plus`
- runs non-interactive online tasks
- acts as the primary remote control plane for agents and channels

### Cloud Run Gateway

Cloud Run is not a peer of the macOS node for interactive work. It is reserved for:

- VPS failover
- burst capacity
- stateless or weak-state non-interactive work

## Routing Policy

### Client-side preference

Clients should prefer the local macOS gateway first:

1. Try `openclaw-local.svc.plus`
2. If unavailable, fall back to `openclaw.svc.plus`

This decision should stay on the client side. Kong should only decide how remote traffic is split between VPS and Cloud Run.

### Remote-side preference

For remote traffic:

1. `openclaw.svc.plus` enters Kong
2. Kong routes to `openclaw-remote.svc.plus` by default
3. Kong fails over to `openclaw-cloud-run.svc.plus` when VPS health or capacity is insufficient

## Configuration Model

Each node keeps its own config file:

- `config/openclaw-local.json`
- `config/openclaw-remote.json`
- `config/openclaw-cloud-run.json`

These files should not be shared or overwritten by other nodes. Node-local concerns differ by design:

- bind mode
- Control UI origin
- browser capabilities
- local paths
- trusted proxy lists
- deployment-specific env

## Shared Memory Model

Nodes should share memory and artifacts, but not the entire runtime state directory.

### Shared across nodes

- long-term memory
- session summaries
- exported artifacts
- attachments
- rebuildable snapshots

### Node-private

- full `OPENCLAW_STATE_DIR`
- workspace working tree and `.git` metadata
- browser profiles
- credentials
- lock files
- temporary files
- logs
- hot session caches

OpenClaw workspace should be treated as node-local or task-local state. If the workspace is Git-managed, multiple active gateways must not mount or write to the same live workspace because `.git` refs, index files, locks, and working tree mutations are not safe to share across concurrent nodes.

Multiple gateways may still synchronize workspace changes through Git's distributed model. In other words: workspaces can be synchronized and merged through Git, but multiple gateways must not share the same live Git working tree.

## TXT Arch Overview

```txt
[Clients]
- macOS client
- iOS client
- other remote clients

[Global Control Plane]
- Kong API Gateway
- auth / JWT / rate limits / presigned URL
- unified remote entrypoint at openclaw.svc.plus
- provider proxy entrypoint such as llm.openclaw.svc.plus

[OpenClaw Gateway Nodes]
- Local macOS gateway:
  best-latency node for browser sessions, login state, and interactive work
- VPS gateway:
  default 24x7 remote execution node
- Cloud Run gateway:
  burst / failover remote node for non-interactive work
- each gateway keeps its own openclaw.json and its own hot runtime state
- gateways do not share OPENCLAW_STATE_DIR directly

[Shared Memory Plane]
- MemOS is the canonical long-term memory system across gateways
- all gateways share the same memory identity model by user_id and memory policy
- MemOS-Cloud-OpenClaw-Plugin is installed on each gateway node
- before_agent_start -> plugin recalls memory from MemOS (/search/memory)
- agent_end -> plugin writes the latest conversation turn back to MemOS (/add/message)
- this is the planned mechanism for multi-OpenClaw multi-gateway memory sync

[Shared Artifact Plane]
- GCS / S3 / OSS stores attachments, exports, snapshots, and recovery payloads
- optional shared mount for desktop/server nodes is provided by JuiceFS, backed by PostgreSQL metadata plus object storage
- object storage may be accessed through direct URLs or Kong-issued presigned URLs
- object storage is not the semantic memory engine

[Traffic and Execution Flow]
1. Client prefers openclaw-local.svc.plus when reachable.
2. If local is unavailable, client falls back to openclaw.svc.plus.
3. Kong authenticates the request and routes to VPS by default.
4. Kong shifts traffic to Cloud Run only for failover or burst.
5. The selected gateway recalls memory from MemOS before execution.
6. The selected gateway writes new memory back to MemOS after execution.
7. Large artifacts are written to object storage, not to shared hot state.

[Design Rule]
- sync memory through MemOS
- sync workspace changes through Git fetch/push/merge, not through a shared live repo mount
- sync artifacts through object storage
- keep execution state local to each gateway
- do not turn multi-gateway OpenClaw into a shared full-state multi-writer system
```

## Planned Feature Direction

1. Solve multi-OpenClaw multi-gateway memory synchronization by introducing one shared memory plane instead of replicating each node's full `OPENCLAW_STATE_DIR`, session cache, browser state, or `openclaw.json`.
2. Integrate [MemOS](https://github.com/cloud-neutral-toolkit/MemOS) plus [MemOS-Cloud-OpenClaw-Plugin](https://github.com/cloud-neutral-toolkit/MemOS-Cloud-OpenClaw-Plugin) so every gateway can recall memory before execution and append new memory after execution through the same lifecycle contract.

## Recommended Storage Layout

### Local macOS Gateway

- `OPENCLAW_CONFIG_PATH=$HOME/.openclaw/openclaw-local.json`
- `OPENCLAW_STATE_DIR=$HOME/.openclaw/local-state`
- workspace path: `$HOME/.openclaw/local-state/workspace`
- optional shared mount: `/opt/data` backed by JuiceFS for shared memory import or export, snapshots, and recovery workflows

### VPS Remote Gateway

- `OPENCLAW_CONFIG_PATH=/data/config/openclaw-remote.json`
- `OPENCLAW_STATE_DIR=/data/remote-state`
- workspace path: `/data/workspace`

### Cloud Run Gateway

- `OPENCLAW_CONFIG_PATH=/data/config/openclaw-cloud-run.json`
- `OPENCLAW_STATE_DIR=/data/cloudrun-state`
- workspace path: `/data/workspace`

### Shared object storage

Use GCS/S3/OSS for shared memory and artifacts only:

- `memory/<user>/<agent>/events/*.jsonl`
- `memory/<user>/<agent>/summary.json`
- `artifacts/<user>/<agent>/...`
- `snapshots/<node>/...`

Prefer append-only or shard-based writes over direct multi-node overwrites of a single `data.json`.

For macOS specifically, keep the live local gateway on local disk first and merge memory artifacts into shared storage on a schedule or at explicit sync points. Use [JuiceFS + PostgreSQL + GCS](juicefs-gcs-mount.md) when `/opt/data` must be shared across Windows / macOS / Linux clients, but do not treat it as the default live state path for `openclaw-local.svc.plus`.

For current storage choices, there are two recommended paths:

- 2-node `macOS + VPS` deployments should prefer Syncthing for `sessions` / `workspace` / shared `memory` files, with node-local SQLite. See [OpenClaw Syncthing Sync Plan](syncthing-sync-plan.md).
- 3+ active nodes or team collaboration should prefer PostgreSQL as the `memory` backend while still keeping `workspace` on Git boundaries. See [OpenClaw 多节点存储场景矩阵](storage-sync-scenarios.md).

When Syncthing is used between macOS and VPS, do not point it at the entire `/opt/data` tree. Restrict synchronization to explicit shared folders such as `sessions`, `workspace`, and `memory`, and keep browser state, logs, credentials, and other hot runtime data node-local. PostgreSQL in this design only addresses distributed `memory` consistency; it does not make the whole OpenClaw runtime safe for shared multi-writer operation.

## Recommended Git Sync Flow

Use Git to synchronize code and workspace outputs across gateways, but only at task boundaries.

### Core rule

- each gateway owns its own local repo and working tree
- gateways exchange changes through Git commits, branches, patches, or bundles
- gateways do not co-mount or co-edit the same live workspace directory

### Recommended baseline

1. Keep one upstream Git remote or one central bare repo as the exchange point.
2. Let each gateway clone or initialize its own local workspace repo.
3. Start each task on a dedicated branch such as `gateway/local/<task-id>`, `gateway/vps/<task-id>`, or `gateway/cloudrun/<task-id>`.
4. During task execution, commit locally as needed without trying to sync the live working tree mid-run.
5. When the task completes, push the branch or export a patch or bundle to the exchange point.
6. Other gateways fetch the new branch and merge, rebase, or cherry-pick it into their own local repo when they are ready.
7. Resolve conflicts only at those synchronization boundaries rather than by sharing one mutable workspace.

### Why this split is correct

- `MemOS` handles semantic memory recall and write-back
- `Git` handles code and workspace history
- object storage handles large files, attachments, snapshots, and exports

Those three planes solve different problems and should stay separate.

## Execution Policy

### Interactive tasks

Run only on the local macOS gateway:

- browser-based tasks
- tasks requiring existing local login state
- human-in-the-loop interaction

### Non-interactive online tasks

Run on VPS by default, with Cloud Run as overflow:

- crawlers
- fetch pipelines
- async research
- scheduled remote tasks

## Final Principle

The architecture should be treated as:

- `Kong` = remote ingress and governance layer
- `Local macOS Gateway` = interactive execution layer
- `VPS / Cloud Run` = online computation layer
- `Object Storage` = shared memory and artifact layer

Do not collapse those four roles back into a shared full-state multi-writer system.
