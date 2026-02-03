# Cross-Repo Task Board

Use this board to track multi-repo initiatives.

## 1) Active Backlog

| ID | Priority | Objective | Impacted Repos | Owner | Status |
| --- | --- | --- | --- | --- | --- |
| CRT-001 | P0 | Internal service auth consistency | `console`, `accounts`, `rag`, `page-reading-agent-backend` | `@shenlan` | PLANNED |
| CRT-002 | P1 | Shared CI cache optimization | `console`, `page-reading-agent-dashboard`, `page-reading-agent-backend` | `@tbd` | TODO |
| CRT-003 | P1 | Release metadata standardization | all deployable repos | `@tbd` | TODO |

## 2) CRT-001 Execution Plan (Real Task)

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

## 3) Request Template (for Codex)

Copy this when creating a new multi-repo change request:

```md
Objective:
Impacted repos:
Constraints:
Acceptance criteria:
Target environment:
```

## 4) Delivery Template (required output)

Codex should answer with:

```md
## Change Scope
## Files Changed
## Risk Points
## Test Commands
## Rollback Plan
```
