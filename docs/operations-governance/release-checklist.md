# Cross-Repo Release Checklist

## A. Release Scope

- [ ] Confirm release objective and impacted repos
- [ ] Confirm owners/reviewers for each impacted repo
- [ ] Confirm backward compatibility expectation

## B. Mandatory Pre-Release Checks

- [ ] Dependency versions are aligned across impacted repos
- [ ] Required env vars are present in SIT/Prod
- [ ] New env vars are documented in `.env.example` (keys only, no secret values)
- [ ] Local run uses `.env`; runtime/prod uses Secret Manager or platform env vars
- [ ] PR diff contains no real secret material (token/password/private key)
- [ ] CI status is green for all impacted repos
- [ ] API contracts are validated (path, payload, auth headers)

## C. Ordered Release Sequence

Release from lower-level dependencies upward:

1. [ ] `gitops` / `iac_modules` (if infra/env changed)
2. [ ] `postgresql.svc.plus` (if schema/connection changed)
3. [ ] `accounts.svc.plus`
4. [ ] `rag-server.svc.plus`
5. [ ] `page-reading-agent-backend`
6. [ ] `moltbot.svc.plus` / `agent.svc.plus` (if impacted)
7. [ ] `console.svc.plus`
8. [ ] `page-reading-agent-dashboard`
9. [ ] `observability.svc.plus` dashboards/alerts updates

## D. Validation After Each Step

- [ ] Health check endpoint is healthy
- [ ] Auth flow works (`X-Service-Token` / session / JWT)
- [ ] Error rate and latency are within threshold
- [ ] No new critical logs in observability

## E. Final Cross-Repo Validation

- [ ] End-to-end auth chain test passed
- [ ] Main user journey smoke test passed
- [ ] Rollback scripts/commands are ready
- [ ] Release notes include impact and fallback

## F. Rollback Order (if needed)

Rollback in reverse release order:

1. `page-reading-agent-dashboard`
2. `console.svc.plus`
3. `moltbot.svc.plus` / `agent.svc.plus`
4. `page-reading-agent-backend`
5. `rag-server.svc.plus`
6. `accounts.svc.plus`
7. `postgresql.svc.plus` and infra change rollback

> If DB schema migration is included, always apply data-safe rollback strategy first.
