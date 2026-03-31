# JP/US to Contabo Migration Execution Checklist

Active execution record for the cutover to `root@jp-xhttp-contabo.svc.plus (46.250.251.132)`.

This file replaces the old single-node validation note and records the migration in time batches, with the current PORD, PRE, and DB tunnel baseline.

## Scope

- Source hosts: `root@us-xhttp.svc.plus`, `root@jp-xhttp.svc.plus`
- Target host: `root@jp-xhttp-contabo.svc.plus`
- Excluded from this cutover: `agent-svc-plus`, `victoria-metrics`, `grafana-server`, `haproxy`

## Service Map

| Layer | Service | Loopback / Host Port | Notes |
| --- | --- | --- | --- |
| PORD | `console.svc.plus` | `127.0.0.1:18080` | Stable console runtime |
| PORD | `accounts.svc.plus` | `127.0.0.1:18081` | Stable accounts runtime |
| PORD | `docs.svc.plus` | `127.0.0.1:18083` | Docs compose service |
| PORD | `rag-server.svc.plus` | `127.0.0.1:18084` | RAG compose service |
| PORD | `x-scope-hub.svc.plus` | `127.0.0.1:18085` | Scope hub compose service |
| PORD | `x-ops-agent.svc.plus` | `127.0.0.1:18086` | Ops agent compose service |
| PRE | `preview-console.svc.plus` | `127.0.0.1:18080` | Console preview entry shares the console runtime binding |
| PRE | `preview-accounts.svc.plus` / `accounts-preview.svc.plus` | `127.0.0.1:28081` | Preview accounts runtime |
| PRE | `x-cloud-flow.svc.plus` | `127.0.0.1:18087` | Cloud flow compose service |
| DB | `stunnel-client` | `127.0.0.1:15432` | Shared internal DB endpoint |
| DB | `dweomer/stunnel-server` | `0.0.0.0:5433` | External TLS endpoint |
| DB | `postgres-extensions:17` | `127.0.0.1:5432` | Local Postgres runtime |

## Batch Log

### Work Order Template

- [ ] Batch 0: Preflight and Freeze
  - [ ] Confirm SSH access to `root@us-xhttp.svc.plus`, `root@jp-xhttp.svc.plus`, and `root@jp-xhttp-contabo.svc.plus`
  - [ ] Freeze any remaining writes on the source host
  - [ ] Snapshot current `docker ps -a`, `ss -ltnp`, and Caddy state
  - [ ] Remove duplicate legacy `jp-xhttp` Caddy site definitions
  - [ ] Record timestamp, operator, and preflight note

- [ ] Batch 1: Sync Images, Configs, and Caddy
  - [ ] Sync `/opt/cloud-neutral/` service directories to the target
  - [ ] Sync `/etc/caddy/conf.d/` to the target
  - [ ] Transfer and load required images
  - [ ] Confirm compose files use the current host-port map
  - [ ] Record timestamp, operator, and sync note

- [ ] Batch 2: DB Tunnel Stack
  - [ ] Recreate `stunnel-client` for `127.0.0.1:15432`
  - [ ] Recreate `dweomer/stunnel-server` for `0.0.0.0:5433`
  - [ ] Verify `postgres-extensions:17` remains on `127.0.0.1:5432`
  - [ ] Confirm tunnel connectivity from both sides
  - [ ] Record timestamp, operator, and tunnel note

- [ ] Batch 3: PORD Services
  - [ ] Start `console.svc.plus` on `18080`
  - [ ] Start `accounts.svc.plus` on `18081`
  - [ ] Start `docs.svc.plus` on `18083`
  - [ ] Start `rag-server.svc.plus` on `18084`
  - [ ] Start `x-scope-hub.svc.plus` on `18085`
  - [ ] Start `x-ops-agent.svc.plus` on `18086`
  - [ ] Verify health endpoints and manifest endpoints
  - [ ] Record timestamp, operator, and PORD note

- [ ] Batch 4: PRE Services
  - [ ] Start `preview-console.svc.plus` on `18080`
  - [ ] Start `preview-accounts.svc.plus` on `28081`
  - [ ] Keep `accounts-preview.svc.plus` as the Caddy alias for the same preview runtime
  - [ ] Start `x-cloud-flow.svc.plus` on `18087`
  - [ ] Verify preview health checks
  - [ ] Record timestamp, operator, and PRE note

- [ ] Batch 5: Caddy Reload and Smoke
  - [ ] Validate `/etc/caddy/Caddyfile`
  - [ ] Restart or reload Caddy cleanly
  - [ ] Confirm the new vhost map is active
  - [ ] Smoke test the public domains
  - [ ] Record timestamp, operator, and smoke note

- [ ] Batch 6: Rollback and Post-Cutover Notes
  - [ ] Write reverse-order rollback steps
  - [ ] Record any service-specific caveats
  - [ ] Mark the batch as exercised or not exercised
  - [ ] Capture final operator notes

### Execution Record

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:00-09:10 CEST` |
| Source | `root@us-xhttp.svc.plus`, `root@jp-xhttp.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | Inventory, port plan, duplicate Caddy cleanup, cutover freeze |
| Verification | `docker ps -a`, `ss -ltnp`, `rg -n "accounts.svc.plus|docs.svc.plus" /etc/caddy /opt/cloud-neutral` |
| Result | `Done` |
| Operator note | Old `jp-xhttp` Caddy entries were identified and removed so `accounts.svc.plus` and `docs.svc.plus` do not collide during reload. |

### Batch 1: Sync Images, Configs, and Caddy

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:10-09:16 CEST` |
| Source | `root@us-xhttp.svc.plus`, `root@jp-xhttp.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | `/opt/cloud-neutral/`, service images, `/etc/caddy/conf.d/` |
| Verification | `docker load`, `docker compose config`, `ls /opt/cloud-neutral/<service>/...`, `ls /etc/caddy/conf.d/` |
| Result | `Done` |
| Operator note | The target now has the migrated compose trees, env files, and Caddy snippets aligned to the new port plan. |

### Batch 2: DB Tunnel Stack

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:16-09:18 CEST` |
| Source | `root@jp-xhttp.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | `stunnel-client`, `dweomer/stunnel-server`, `postgres-extensions:17` |
| Verification | `docker compose up -d --force-recreate`, `docker logs`, `ss -ltnp` |
| Result | `Done` |
| Operator note | `stunnel-client` is the shared DB endpoint for other services, and `stunnel-server` is now exposed on `0.0.0.0:5433` while Postgres stays on `127.0.0.1:5432`. |

### Batch 3: PORD Services

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:18-09:20 CEST` |
| Source | `root@us-xhttp.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | `console`, `accounts`, `docs`, `rag-server`, `x-scope-hub`, `x-ops-agent` |
| Verification | `docker compose ps`, `curl -sf http://127.0.0.1:<port>/healthz`, `curl -sf http://127.0.0.1:18085/manifest` |
| Result | `Done` |
| Operator note | The PORD set was brought up with the new host-port map and kept separate from the PRE preview route entries. |

### Batch 4: PRE Services

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:20-09:22 CEST` |
| Source | `root@us-xhttp.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | `preview-console`, `preview-accounts`, `x-cloud-flow` |
| Verification | `docker compose ps`, `curl -sf http://127.0.0.1:28081/healthz`, `curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:18087/healthz` |
| Result | `Done` |
| Operator note | `preview-console.svc.plus` is documented as a console preview entry on the same console runtime binding, while `preview-accounts.svc.plus` uses the dedicated `28081` preview port. |

### Batch 5: Caddy Reload and End-to-End Smoke

| Field | Value |
| --- | --- |
| Time window | `2026-03-31 09:22-09:25 CEST` |
| Source | `root@jp-xhttp-contabo.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | Caddy validation, reload, public smoke checks |
| Verification | `caddy validate --config /etc/caddy/Caddyfile`, `systemctl reset-failed caddy`, `systemctl start caddy`, `curl -skf https://<domain>/healthz` |
| Result | `Done` |
| Operator note | The old `jp-xhttp` duplicate vhost definitions were removed first, so Caddy could reload cleanly against the updated release map, and the import list now includes both `*.caddy` and `*.conf` so `x-scope-hub`, `x-ops-agent`, and `x-cloud-flow` actually enter the running config. The legacy `*-us-xhttp-*` alias files on the target were renamed to `*-contabo-*` to match the new host label. |

### Batch 6: Rollback and Post-Cutover Notes

| Field | Value |
| --- | --- |
| Time window | `post-cutover` |
| Source | `root@jp-xhttp-contabo.svc.plus` |
| Target | `root@jp-xhttp-contabo.svc.plus` |
| Scope | Reverse-order rollback, host cleanup, audit notes |
| Verification | `docker compose ps`, `ss -ltnp`, reverse Caddy restore if needed |
| Result | `Done` |
| Operator note | Rollback order remains `x-cloud-flow` -> `x-ops-agent` -> `x-scope-hub` -> `rag-server` -> `docs` -> `accounts` -> DB tunnel stack -> Caddy, and the source host old containers were stopped after the authoritative DNS switch. |

## Current State

| Item | Status | Note |
| --- | --- | --- |
| `console.svc.plus` | Ready | `127.0.0.1:18080` |
| `console-8fa9cd3-contabo.svc.plus` | Ready | `127.0.0.1:18080` |
| `accounts.svc.plus` | Ready | `127.0.0.1:18081` |
| `docs.svc.plus` | Ready | `127.0.0.1:18083` |
| `rag-server.svc.plus` | Ready | `127.0.0.1:18084` |
| `x-scope-hub.svc.plus` | Ready | `127.0.0.1:18085` |
| `x-ops-agent.svc.plus` | Ready | `127.0.0.1:18086` |
| `preview-console.svc.plus` | Ready | Console runtime route on `18080` |
| `preview-accounts.svc.plus` / `accounts-preview.svc.plus` | Ready | `127.0.0.1:28081` |
| `x-cloud-flow.svc.plus` | Ready | `127.0.0.1:18087` |
| DB tunnel | Ready | `stunnel-client` on `15432`, `stunnel-server` on `5433`, `postgresql-svc-plus` on `5432` |
| Source host old containers | Drained | `us-xhttp` legacy service containers stopped after cutover |
| Caddy import | Updated | `/etc/caddy/Caddyfile` now imports both `*.caddy` and `*.conf` |
| Caddy aliases | Updated | Target `/etc/caddy/conf.d` alias files now use `contabo` instead of `us-xhttp` |
