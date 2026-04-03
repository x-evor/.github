# Cross-Repo Task Board

Use this board to track multi-repo initiatives.

## 1) Active Backlog

| ID | Priority | Objective | Impacted Repos | Owner | Status |
| --- | --- | --- | --- | --- | --- |
| CRT-001 | P0 | Internal service auth consistency | `console`, `accounts`, `rag`, `page-reading-agent-backend` | `@shenlan` | PLANNED |
| CRT-002 | P1 | Shared CI cache optimization | `console`, `page-reading-agent-dashboard`, `page-reading-agent-backend` | `@tbd` | TODO |
| CRT-003 | P1 | Release metadata standardization | all deployable repos | `@tbd` | TODO |
| CRT-004 | P0 | Accounts + Console RBAC / 多租户 / Token model convergence | `console`, `accounts`, control repo | `@shenlan` | IN_PROGRESS |
| CRT-005 | P0 | Externalize docs/blog delivery via `docs.svc.plus` + `docs-agent` | `docs.svc.plus`, `console.svc.plus`, `knowledge`, `openclaw.svc.plus`, control repo | `@shenlan` | IN_PROGRESS |
| CRT-006 | P1 | Shared `app-service` Helm contract for core / extsvc workloads | `artifacts`, `gitops`, `console.svc.plus`, `accounts.svc.plus`, `rag-server.svc.plus`, `docs.svc.plus`, `x-cloud-flow.svc.plus`, `x-ops-agent.svc.plus`, `x-scope-hub.svc.plus`, `postgresql.svc.plus` | `@shenlan` | PLANNED |

## 2.1) GitOps Dependency Maps

Use these two views to reason about cluster rollout order before changing `dependsOn`.

### Current State

This is the legacy dependency shape that caused `pre-stack` to wait on the heavier infrastructure gate:

```mermaid
graph TD
  PlatformK3s["platform-k3s"]
  Obs["observability-stack"]

  Infra["database-stack\n(postgresql)"]

  PreStack["pre-stack"]
  AccountsProd["accounts-prod"]
  ConsoleProd["console-prod"]

  AccountsPre["accounts-pre"]
  ConsolePre["console-pre"]

  PlatformK3s --> Obs
  PlatformK3s --> Infra
  PlatformK3s --> PreStack

  Infra --> AccountsProd
  Infra --> AccountsPre

  PreStack --> AccountsPre
  PreStack --> ConsolePre

  AccountsProd --> ConsoleProd
  AccountsPre --> ConsolePre
```

### Target State

This is the intended business rollout chain for the core services after the GitOps dependency cleanup:

```mermaid
graph TD
  PlatformK3s["platform-k3s"]
  Obs["observability-stack"]

  Infra["database-stack\n(postgresql)"]

  AccountsProd["accounts-prod"]
  ConsoleProd["console-prod"]

  AccountsPre["accounts-pre"]
  ConsolePre["console-pre"]

  PlatformK3s --> Obs
  PlatformK3s --> Infra

  Infra --> AccountsProd
  AccountsProd --> ConsoleProd

  Infra --> AccountsPre
  AccountsPre --> ConsolePre
```

### Why this order

- `platform-k3s` is the cluster foundation, so platform and infra stacks must wait for it.
- `observability-stack` is a platform concern and only needs the cluster foundation.
- `database-stack` provides shared runtime services such as PostgreSQL, so core business services should wait for it.
- `accounts` is the auth and account core for both `pre` and `prod`.
- `console` depends on `accounts`, so it should reconcile only after the auth layer is ready.
- Keeping the chain explicit prevents unrelated infrastructure health from blocking business rollout in surprising ways.

## 3) CRT-001 Execution Plan (Real Task)

**Objective**
- Standardize internal service auth (`X-Service-Token`) behavior and error handling across the core service chain.

**Impacted repos**
- `console.svc.plus`
- `accounts.svc.plus`
- `rag-server.svc.plus`
- `page-reading-agent-backend`

**Phase plan**
- **Phase 1 (design freeze):** align header contract, middleware behavior, and error format (`401`/`403`).
- **Phase 2 (implementation):** apply auth checks in each repo with shared naming and consistent logs.
- **Phase 3 (verification):** run unit + integration + service-chain smoke tests.
- **Phase 4 (release):** deploy in checklist order from backend dependencies to frontend callers.

**Target files (expected)**
- `console.svc.plus`: API proxy routes and internal auth helper.
- `accounts.svc.plus`: middleware/auth validation and internal health endpoint behavior.
- `rag-server.svc.plus`: middleware/auth validation and internal route guards.
- `page-reading-agent-backend`: middleware and route-level guard integration.

**Risk points**
- Token mismatch across environments (`.env` vs cloud secret manager).
- Mixed status codes breaking frontend retry/error handling.
- Hidden bypass route missing middleware attachment.

**Test commands (baseline)**
- `console.svc.plus`: `yarn lint && yarn test`
- `accounts.svc.plus`: `go test ./...`
- `rag-server.svc.plus`: `go test ./...`
- `page-reading-agent-backend`: `yarn test` (or repo test command)
- Control repo chain check: `bash test/e2e/service-auth-integration-test.sh`

**Rollback plan**
- Revert in reverse dependency order: callers first, then backend services.
- Keep old token value available until all services are rolled back.
- If partial failure happens, disable only newly added strict routes first.

## 4) Request Template (for Codex)

Copy this when creating a new multi-repo change request:

```md
Objective:
Impacted repos:
Constraints:
Acceptance criteria:
Target environment:
Validation mode:
Gate entry:
```

## 4.1) CRT-004 Execution Plan (Real Task)

**Objective**
- Align `accounts.svc.plus` and `console.svc.plus` on a real tenant-aware RBAC and token ownership model.

**Impacted repos**
- `accounts.svc.plus`
- `console.svc.plus`
- `github-org-cloud-neutral-toolkit`

**Phase plan**
- **P0:** replace legacy `public_token` flow with one-time `exchange_code`, unify console permission gates, define platform-level public token visibility.
- **P1:** align session contract with real backend data model, add integration registry and token ownership matrix.
- **P2:** introduce tenant membership and tenant-scoped RBAC in `accounts`, switch console to tenant-aware access control.
- **P3:** support shared mode and dedicated mode component authorization, credential ownership, and audit trails.

**Key design defaults**
- Platform tokens are visible only to `root / platform_admin` by default.
- `INTERNAL_SERVICE_TOKEN` remains platform-internal and must not represent end-user identity.
- Tenant authorization is evaluated before component-level authorization.
- `console` BFF routes must not rely on role-only checks when a permission gate exists.

**Primary deliverables**
- Security audit:
  - `docs/security/accounts-console-rbac-multitenancy-audit-2026-03-17.md`
- Target architecture:
  - `docs/architecture/accounts-console-tenant-rbac-target-architecture.md`
- Follow-on implementation backlog:
  - this section (`CRT-004`)

**Risk points**
- False multi-tenant semantics in frontend session payload without backend tenant ownership.
- Tenant-free session and shared token boundaries still exist even after the legacy `public_token` flow was removed.
- Shared integration tokens without explicit owner/scope/visibility governance.
- Console admin BFF routes drifting away from backend permission semantics.

**Verification baseline**
- `accounts.svc.plus`: schema, auth middleware, token exchange, admin permission gates
- `console.svc.plus`: session normalization, access control utilities, admin BFF route guards, integration token resolvers
- Control repo: audit/architecture docs and backlog stay decision-complete

## 4.2) Stable Release Gate Template (required output)

Use this template when asking Codex to verify a stable release candidate:

```md
Mode:
Service:
Track:
Service ref:
Smoke URL:
Expected status:
Required evidence:
```

**Mode defaults**
- `local`: repo-local config/doc validation only
- `stable`: repo-local validation plus live smoke against the stable domain
- Gate entry: `.github/workflows/stable_release_gate.yml`

## 5) Delivery Template (required output)

Codex should answer with:

```md
## Change Scope
## Files Changed
## Risk Points
## Test Commands
## Rollback Plan
```

## 5.1) CRT-005 Execution Plan (Real Task)

**Objective**
- Move `/docs` and `/blogs` content delivery out of `console.svc.plus` build-time sync and into `docs.svc.plus`, then expose document retrieval and controlled updates as `docs-agent` behind the OpenClaw gateway.

**Impacted repos**
- `docs.svc.plus`
- `console.svc.plus`
- `knowledge`
- `openclaw.svc.plus`
- `github-org-cloud-neutral-toolkit`

**Phase plan**
- **Phase 1:** ship read-only docs/blog service APIs and reload flow in `docs.svc.plus`
- **Phase 2:** switch `console.svc.plus` `/docs`, `/blogs`, sitemap, and latest blogs feed to the new service
- **Phase 3:** register `docs-agent` in gateway as read-only
- **Phase 4:** enable `docs.plan_update`
- **Phase 5:** enable confirm-required `docs.apply_update`

**Key defaults**
- `knowledge` is the single source of truth
- browser traffic does not call `docs.svc.plus` directly
- all `/api/v1/*` reads require `X-Service-Token`
- `docs-agent` writes are restricted to `knowledge/docs/**` and `knowledge/content/**`

**Risk points**
- UI regression if remote HTML differs from current markdown rendering
- reload or pull failures can desync source and index snapshots
- unsafe path handling in `docs-agent` would be release-blocking
- gateway policy drift could allow apply without confirmation

## 5.2) CRT-006 Execution Plan (Real Task)

**Objective**
- Converge the core, extsvc, and database workloads on the shared `app-service` Helm contract, while keeping `stunnel-client` separate and `postgresql` server-side stunnel inline.

**Impacted repos**
- `artifacts`
- `gitops`
- `console.svc.plus`
- `accounts.svc.plus`
- `rag-server.svc.plus`
- `docs.svc.plus`
- `x-cloud-flow.svc.plus`
- `x-ops-agent.svc.plus`
- `x-scope-hub.svc.plus`
- `postgresql.svc.plus`
- `github-org-cloud-neutral-toolkit`

**Phase plan**
- **Phase 1 (contract freeze):** add the pod-spec hooks required by `rag-server` and `docs` to the reusable chart, and lock down probe defaults for `console`.
- **Phase 2 (implementation):** update service overlays to use the shared chart contract, with `rag-server` config mounts and `docs` knowledge-repo mounts modeled explicitly.
- **Phase 3 (special cases):** keep `stunnel-client` as a separate chart, preserve inline `stunnel-server` in `postgresql`, and treat `x-scope-hub` as a single selected runtime component rather than a multi-container pod.
- **Phase 4 (verification):** run chart lint/template checks plus namespace `kustomize build` for `core-prod`, `core-pre`, and `extsvc`.
- **Phase 5 (publish / rollout):** bump chart consumers in GitOps only after the chart package and image release contracts are aligned.

**Risk points**
- `docs.svc.plus` will fail if the knowledge checkout is not mounted or synced at runtime.
- `rag-server.svc.plus` will fail if its config file is not mounted and `CONFIG_PATH` is not set consistently.
- `console.svc.plus` health probing on `/healthz` is unsafe until the probe path is changed to `/`.
- `x-scope-hub.svc.plus` has multiple internal runtimes, so the shared chart must pick a single deployable entrypoint.
- `stunnel-client` ownership must stay separate from the PostgreSQL pod to avoid reintroducing hidden coupling.

**Test commands (baseline)**
- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/artifacts/oci/charts && helm lint ./apps/app-service`
- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/artifacts/oci/charts && helm template console-prod ./apps/app-service -f /Users/shenlan/workspaces/cloud-neutral-toolkit/gitops/infra/apps/core/console/base/values.yaml -f /Users/shenlan/workspaces/cloud-neutral-toolkit/gitops/infra/apps/core/console/prod/values.yaml`
- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/gitops && kustomize build apps/clusters/prod`
- `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/gitops && kustomize build apps/clusters/pre`

**Rollback plan**
- Roll back GitOps overlays first, then revert the shared chart contract, then restore any service-specific probe or mount overrides.
- Keep `stunnel-client` and `stunnel-server` rollback steps separate so the database path can be restored independently of app workloads.
