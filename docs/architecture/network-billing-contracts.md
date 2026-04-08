# Network Billing Contracts

This document defines the minimum v1 contract for the network billing control plane.

## 1. Scope

- `xray-core` is raw traffic stats only.
- `xray-exporter` translates raw stats into enriched metrics and snapshot payloads.
- `billing-service` computes minute deltas and writes replay-safe facts into PostgreSQL.
- `accounts.svc.plus` reads usage and billing facts from PostgreSQL only.
- `console.svc.plus` reads usage and billing data from `accounts.svc.plus` only.
- `Prometheus` and `Grafana` are observability consumers only.

## 2. Shared Identity Contract

The following fields are mandatory across exporter output, billing snapshots, persisted rows, and cross-repo verification:

| Field | Type | Meaning |
| --- | --- | --- |
| `uuid` | string | End-user traffic identity from Xray |
| `email` | string | Human/account binding resolved by exporter cache |
| `node_id` | string | Stable node identifier for the emitting proxy node |
| `env` | string | Deployment environment such as `prod` or `preview` |
| `inbound_tag` | string | Xray inbound tag for line / path / product differentiation |

Rules:

- `uuid + node_id + env + inbound_tag` must stay stable for the same emitted stream.
- `email` may be temporarily missing during cache miss or backend outage, but the key set above must still be emitted.
- `accounts.svc.plus` and `console.svc.plus` must not synthesize these fields from Prometheus queries.

## 3. Observability Path

```text
xray-core -> xray-exporter -> Prometheus -> Grafana
```

This path exists for visibility only. It is never a billing source.

### 3.1 `xray-exporter` minimum responsibilities

- Poll Xray stats on a fixed interval.
- Translate cumulative per-UUID counters into labeled metric series.
- Maintain a refreshable `uuid -> email` cache.
- Expose Prometheus metrics.
- Expose or retain an internal normalized snapshot shape suitable for billing ingestion.
- Degrade gracefully when Xray or the identity store is temporarily unavailable.

### 3.2 `xray-exporter` minimum metric contract

Required metric families:

| Metric | Type | Required labels |
| --- | --- | --- |
| `xray_user_uplink_bytes` | counter/gauge snapshot of cumulative bytes | `uuid,email,node_id,env,inbound_tag` |
| `xray_user_downlink_bytes` | counter/gauge snapshot of cumulative bytes | `uuid,email,node_id,env,inbound_tag` |
| `xray_exporter_collect_success` | gauge | `node_id,env` |
| `xray_exporter_collect_timestamp_seconds` | gauge | `node_id,env` |

Notes:

- v1 billing logic assumes exporter traffic metrics are cumulative counters per identity stream.
- If `email` cannot be resolved, exporter should emit `email="unknown"` rather than dropping the series.
- Exporter may expose more metrics, but these metrics and labels are the release gate.

### 3.3 `xray-exporter` normalized snapshot shape

This is the minimum payload shape billing-service must be able to consume, whether by internal call, queue, or file boundary:

```json
{
  "collected_at": "2026-04-08T12:00:00Z",
  "node_id": "jp-xhttp-contabo.svc.plus",
  "env": "prod",
  "samples": [
    {
      "uuid": "uuid-1",
      "email": "user@example.com",
      "inbound_tag": "xhttp-premium",
      "uplink_bytes_total": 1024,
      "downlink_bytes_total": 2048
    }
  ]
}
```

Contract rules:

- `collected_at` uses UTC.
- Sample counters are cumulative totals from Xray, not deltas.
- Missing `email` must not block emission of the sample.

## 4. Billing Path

```text
xray-core -> xray-exporter -> billing-service -> PostgreSQL -> accounts.svc.plus -> console.svc.plus
```

This path owns usage and billing truth.

### 4.1 `billing-service` minimum responsibilities

- Ingest exporter snapshots.
- Bucket data by UTC minute.
- Compute positive deltas from cumulative counters.
- Protect against negative deltas caused by restart or counter reset.
- Write replay-safe minute facts into PostgreSQL.
- Reconcile late or missing minutes.
- Recover safely after process restart.

### 4.2 `billing-service` minimum ingestion contract

Billing-service accepts the normalized exporter snapshot defined above and persists minute-level facts using:

- minute bucket: `date_trunc('minute', collected_at at time zone 'UTC')`
- identity key: `uuid + node_id + env + inbound_tag`

### 4.3 `billing-service` write semantics

- All billing writes must be idempotent.
- Minute rows must be safe to replay for the same minute and identity key.
- Negative deltas must never reduce billed usage.
- Late-arriving minutes must update the same minute bucket rather than append a second logical row.

## 5. PostgreSQL Schema Draft

### 5.1 `traffic_stat_checkpoints`

Purpose: remember the last cumulative counters seen by billing-service.

| Column | Type | Notes |
| --- | --- | --- |
| `uuid` | text | part of unique identity |
| `node_id` | text | part of unique identity |
| `env` | text | part of unique identity |
| `inbound_tag` | text | part of unique identity |
| `email` | text | last resolved email |
| `last_collected_at` | timestamptz | last accepted snapshot timestamp |
| `uplink_bytes_total` | bigint | last cumulative uplink |
| `downlink_bytes_total` | bigint | last cumulative downlink |
| `updated_at` | timestamptz | row maintenance |

Recommended uniqueness:

- unique index on `(uuid, node_id, env, inbound_tag)`

### 5.2 `traffic_minute_buckets`

Purpose: minute-level usage fact table for accounts aggregation.

| Column | Type | Notes |
| --- | --- | --- |
| `minute_ts` | timestamptz | UTC minute bucket |
| `uuid` | text | billing identity |
| `email` | text | denormalized for audit/debug |
| `node_id` | text | billing identity |
| `env` | text | billing identity |
| `inbound_tag` | text | billing identity |
| `uplink_bytes` | bigint | minute delta |
| `downlink_bytes` | bigint | minute delta |
| `total_bytes` | bigint | derived delta |
| `rating_status` | text | e.g. `rated`, `pending_reconcile` |
| `source_revision` | text | optional exporter/billing revision |
| `created_at` | timestamptz | row creation |
| `updated_at` | timestamptz | row update |

Recommended uniqueness:

- unique index on `(minute_ts, uuid, node_id, env, inbound_tag)`

### 5.3 `billing_ledger`

Purpose: rated monetary ledger derived from minute facts.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | text/uuid | immutable ledger id |
| `account_uuid` | text | account dimension |
| `bucket_start` | timestamptz | rated usage range start |
| `bucket_end` | timestamptz | rated usage range end |
| `entry_type` | text | e.g. `traffic_charge`, `reconcile_adjustment` |
| `rated_bytes` | bigint | rated usage |
| `amount_delta` | numeric | balance delta |
| `balance_after` | numeric | post-entry balance |
| `pricing_rule_version` | text | rule traceability |
| `created_at` | timestamptz | immutable append timestamp |

### 5.4 `account_quota_states`

Purpose: current usage/balance/quota snapshot used by `accounts.svc.plus`.

| Column | Type | Notes |
| --- | --- | --- |
| `account_uuid` | text | primary key |
| `remaining_included_quota` | bigint | remaining included bytes |
| `current_balance` | numeric | post-rating balance |
| `arrears` | boolean | payment state |
| `throttle_state` | text | runtime action state |
| `suspend_state` | text | runtime action state |
| `last_rated_bucket_at` | timestamptz | replay/reconcile tracking |
| `effective_at` | timestamptz | business effective time |
| `updated_at` | timestamptz | maintenance |

## 6. API Boundary Expectations

### 6.1 `accounts.svc.plus`

Accounts usage and billing APIs must:

- read from PostgreSQL-backed store layers only
- include `sourceOfTruth = "postgresql"` in usage and billing responses
- avoid any direct dependency on Prometheus queries

### 6.2 `console.svc.plus`

Console usage and billing UI must:

- fetch usage and billing summaries from `accounts.svc.plus`
- display source-of-truth metadata from accounts
- treat Grafana embeds as observability views only

## 7. Non-Goals for v1

- Billing directly from Prometheus
- Anomaly detection as a blocking dependency for billing
- Autoscaling decision engines inside the billing write path
- Frontend-side traffic calculations outside `accounts.svc.plus`
