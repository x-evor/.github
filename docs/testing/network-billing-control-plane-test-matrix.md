# Network Billing Control Plane Test Matrix

This matrix is the executable validation baseline for `CRT-007`.

## 1. Contract Tests

### 1.1 Exporter metric contract

Goal:

- Verify exporter emits the required metric families with the required labels.

Checks:

- `xray_user_uplink_bytes` exists
- `xray_user_downlink_bytes` exists
- every traffic sample includes `uuid,email,node_id,env,inbound_tag`
- cache-miss behavior emits `email="unknown"` instead of dropping the sample

Suggested commands:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xray-exporter && go test ./...`
- `curl -fsS http://127.0.0.1:PORT/metrics | rg "xray_user_(up|down)link_bytes"`

### 1.2 Billing ingestion contract

Goal:

- Verify billing-service accepts the normalized exporter snapshot and computes minute buckets in UTC.

Checks:

- `collected_at` is normalized to UTC minute
- identity key is `uuid + node_id + env + inbound_tag`
- cumulative counters are accepted as totals, not deltas

Suggested commands:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/billing-service && go test ./...`

## 2. Persistence and Idempotency

### 2.1 Minute bucket idempotency

Goal:

- Replaying the same snapshot does not duplicate minute rows.

Checks:

- same minute + identity writes produce one logical row
- repeated processing preserves `total_bytes`

### 2.2 Ledger idempotency

Goal:

- Replaying a rated minute does not duplicate ledger charges.

Checks:

- duplicate writes do not append a second charge
- `balance_after` stays deterministic

### 2.3 Restart recovery

Goal:

- billing-service can restart from checkpoints without negative or double deltas.

Checks:

- checkpoint table restores previous cumulative totals
- next valid minute continues from last accepted state

## 3. Replay and Reconciliation

### 3.1 Late-arriving minute replay

Goal:

- Missing or delayed minutes can be backfilled into the correct UTC bucket.

Checks:

- late minute updates the intended `minute_ts`
- no second logical bucket is created for the same identity key

### 3.2 Negative delta protection

Goal:

- Counter resets from Xray do not create negative billed usage.

Checks:

- negative delta is dropped or converted into a reset path
- billing does not subtract from already-rated usage

### 3.3 Missing minute reconciliation

Goal:

- scheduled reconciliation can fill a gap after exporter or billing downtime.

Checks:

- gap is detected
- replay writes are idempotent
- account aggregates converge after reconciliation

## 4. Accounts and Console Source-of-Truth Tests

### 4.1 `accounts.svc.plus`

Goal:

- Lock usage and billing APIs to PostgreSQL-backed truth only.

Checks:

- `/api/account/usage/summary` returns `sourceOfTruth = postgresql`
- `/api/account/usage/buckets` returns `sourceOfTruth = postgresql`
- `/api/account/billing/summary` returns `sourceOfTruth = postgresql`

Command:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus && go test ./api/...`

### 4.2 `console.svc.plus`

Goal:

- Lock UI to accounts-backed usage and billing reads only.

Checks:

- fetch layer reads `/api/account/usage/summary`
- `SubscriptionPanel` renders accounts-only wording
- `SubscriptionPanel` renders `sourceOfTruth = postgresql`

Command:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/console.svc.plus && yarn test:unit src/modules/extensions/builtin/user-center/lib/fetchAccountUsage.test.ts src/modules/extensions/builtin/user-center/account/__tests__/SubscriptionPanel.test.tsx`

## 5. Multi-Node and Multi-Env Isolation

Goal:

- Ensure usage from one node or environment does not bleed into another.

Checks:

- `prod` and `preview` rows remain isolated
- node-level replay does not affect sibling nodes
- aggregate queries group by account while preserving node/env filtering semantics

Suggested coverage:

- fixtures with same `uuid` across different `node_id`
- fixtures with same `uuid` across `prod` and `preview`

## 6. Failure-Mode Matrix

| Failure mode | Expected behavior | Must not happen |
| --- | --- | --- |
| Xray unavailable | exporter marks scrape failure and preserves last good state for observability | billing invents synthetic usage |
| PostgreSQL unavailable | exporter can still expose metrics; billing fails closed and retries | billing buffers hidden truth in memory as final state |
| stale cache entry | exporter emits stable labels with last known or `unknown` email | sample is dropped silently |
| negative delta | reset path or guarded skip | previously billed usage decreases |
| duplicate minute write | upsert / uniqueness keeps one logical bucket | duplicate charges |
| late-arriving minute | reconciliation updates existing minute bucket | second logical row for same minute identity |

## 7. Release Gate Commands

Control repo:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit && rg -n "sourceOfTruth|xray-exporter|billing-service|minute_ts|negative delta|late-arriving" docs/architecture docs/testing docs/operations-governance`

Accounts:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus && go test ./api/...`

Console:

- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/console.svc.plus && yarn test:unit src/modules/extensions/builtin/user-center/lib/fetchAccountUsage.test.ts src/modules/extensions/builtin/user-center/account/__tests__/SubscriptionPanel.test.tsx`

## 8. Exit Criteria

`CRT-007` can move from design freeze to implementation only when:

- interface and schema contracts are documented
- `accounts` source-of-truth regressions pass
- `console` source-of-truth regressions pass
- replay, negative-delta, and multi-env test cases are written into the delivery backlog
