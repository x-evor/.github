# Observability Monitoring Chain

## Target Chain

Four production nodes:

- `postgresql.svc.plus`
- `us-xhttp.svc.plus`
- `hk-xhttp.svc.plus`
- `jp-xhttp.svc.plus`

Data path:

1. `node_exporter` + `process_exporter` + host logs on each node
2. Collected by `vector` agent
3. Sent through HTTPS ingest endpoints on `observability.svc.plus` (Alloy ingest layer)
4. Routed to backend stores:
   - Metrics: `127.0.0.1:8428` (VictoriaMetrics)
   - Logs: `127.0.0.1:9428` (VictoriaLogs)
   - Traces: `127.0.0.1:10428` (VictoriaTraces)

Agent-side chain (simplified):

`node_exporter / process_exporter -> vector -> HTTPS -> observability.svc.plus (Alloy)`

Special case (observability host self-monitoring):

`node_exporter / process_exporter -> vector -> 127.0.0.1 -> Victoria* backend`

## Ingest Endpoints

- Metrics write: `https://observability.svc.plus/ingest/metrics/api/v1/write`
- Logs write: `https://observability.svc.plus/ingest/logs/insert` (Vector Loki sink appends `/loki/api/v1/push`)
- Traces write: `https://observability.svc.plus/ingest/otlp/v1/traces`

## Server-side Topology (`observability.svc.plus`)

Gateway and UI:

- `caddy` (TLS termination at `https://observability.svc.plus`)
- `grafana` (dashboard and data source entry)
- `insight` (query/explore workbench)

Backend services:

- `VictoriaMetrics` (`127.0.0.1:8428`): time-series storage, Prometheus-compatible API / VMUI
- `VictoriaLogs` (`127.0.0.1:9428`): centralized structured logs, receives Vector log streams
- `VictoriaTraces` (`127.0.0.1:10428`): tracing/event storage for slow SQL and request tracing

Traffic flow:

`caddy (HTTPS)` -> `grafana/insight` + ingest routes -> `VictoriaMetrics/VictoriaLogs/VictoriaTraces`

## Agent Install / Upgrade

Default behavior is deploy/upgrade (idempotent).

```bash
curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/observability.svc.plus/main/scripts/agent-install.sh \
  | bash -s -- --endpoint https://observability.svc.plus/ingest/otlp
```

Optional lifecycle actions:

```bash
# reset
curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/observability.svc.plus/main/scripts/agent-install.sh \
  | bash -s -- --action reset -y --endpoint https://observability.svc.plus/ingest/otlp

# uninstall
curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/observability.svc.plus/main/scripts/agent-install.sh \
  | bash -s -- --action uninstall -y
```

## Server Install / Upgrade

```bash
curl -fsSL "https://raw.githubusercontent.com/cloud-neutral-toolkit/observability.svc.plus/main/scripts/server-install.sh?$(date +%s)" \
  | bash -s -- observability.svc.plus
```

The server script configures HTTPS ingest routing (caddy/nginx compatible) and keeps repeated execution safe.

## Ops Validation Checklist

On each node:

- `systemctl is-active node_exporter process_exporter vector`
- `curl -s http://127.0.0.1:9100/metrics | head`
- `curl -s http://127.0.0.1:9256/metrics | head`

On `observability.svc.plus`:

- `curl -s http://127.0.0.1:8428/api/v1/query --data-urlencode 'query=up{job="node"}'`
- `curl -s http://127.0.0.1:9428/select/logsql/query -d 'query=* | limit 5'`
- `ss -lntp | grep -E ':8428|:9428|:10428'`

Grafana homepage target:

- `https://observability.svc.plus/grafana/d/home/homepage?orgId=1`
