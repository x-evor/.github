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
- [ ] Cloud desktop changes document Azure/GCP auth requirements and keep VM state files out of Git
- [ ] Cloud desktop changes require non-empty `allowed_cidrs` and cleanup targeting only toolkit-tagged resources
- [ ] Control-plane release metadata is updated when repo/domain/port/catalog entries change
- [ ] Required GitHub Actions secrets exist and any workflow SSH or HTTPS bootstrap overrides are set correctly for the single-node release workflow
- [ ] Service-specific secrets are split correctly: public defaults checked in, secret-only fields in GitHub Secrets
- [ ] For release-enabled services, the target service repository ref is updated and pushed before dispatching the release workflow
- [ ] Stable domains already point to the single deploy host before promoting a new revision
- [ ] `docs.svc.plus` has `KNOWLEDGE_REPO_PATH`, `DOCS_SERVICE_PORT`, `DOCS_RELOAD_INTERVAL`, and `INTERNAL_SERVICE_TOKEN` configured
- [ ] The deploy host has a readable `knowledge` Git checkout mounted at the `docs.svc.plus` host path expected by the release vars
- [ ] `console.svc.plus` has `DOCS_SERVICE_URL` / `DOCS_SERVICE_INTERNAL_URL` configured for the target environment
- [ ] Gateway-side `docs-agent` policy keeps `plan_update` and `apply_update` separate, with confirmation required for apply
- [ ] The control-plane release gate entry exists at `.github/workflows/stable_release_gate.yml`
- [ ] `python3 scripts/github-actions/stable-release-gate.py --mode local --service <service> --track <track> --service-ref <ref>` passes before any stable promotion
- [ ] `python3 scripts/github-actions/stable-release-gate.py --mode stable --service <service> --track <track> --service-ref <ref>` passes against the live stable domain before release sign-off
- [ ] `release/*` protection is applied (ruleset/branch protection) and only release managers can update it
- [ ] CI status is green for all impacted repos
- [ ] API contracts are validated (path, payload, auth headers)
- [ ] Single-node k3s platform changes keep `Traefik` disabled and reserve `servicelb` for the ingress entrypoint
- [ ] Flux root sync target and child `Kustomization` paths match the `gitops/infra/` tree
- [ ] New GitOps platform secrets are sourced from runtime secret stores or workflow secrets only; no real values are committed, including SSH keys, HTTPS usernames/passwords, and bearer tokens
- [ ] Inventory entries may reference secret file paths or runtime materialization inputs, but must not contain plaintext private keys, passwords, or tokens
- [ ] Vault, ESO, and Reloader rollout order is documented for the release

## C. Ordered Release Sequence

Release from lower-level dependencies upward:

1. [ ] `gitops` / `iac_modules` (if infra/env changed)
2. [ ] `postgresql.svc.plus` (if schema/connection changed)
3. [ ] `accounts.svc.plus`
4. [ ] `rag-server.svc.plus`
5. [ ] `docs.svc.plus`
6. [ ] `openclaw.svc.plus` / AI gateway config (if impacted)
7. [ ] `page-reading-agent-backend`
8. [ ] `moltbot.svc.plus` / `agent.svc.plus` (if impacted)
9. [ ] `console.svc.plus`
10. [ ] `page-reading-agent-dashboard`
11. [ ] `observability.svc.plus` dashboards/alerts updates

## D. Validation After Each Step

- [ ] Health check endpoint is healthy
- [ ] Auth flow works (`X-Service-Token` / session / JWT)
- [ ] Error rate and latency are within threshold
- [ ] No new critical logs in observability

## E. Final Cross-Repo Validation

- [ ] End-to-end auth chain test passed
- [ ] Main user journey smoke test passed
- [ ] `/docs`, `/docs/<collection>/<slug>`, `/blogs`, and `/blogs/<slug>` load through `docs.svc.plus`
- [ ] Gateway can invoke `docs-agent` read operations successfully
- [ ] If write mode is enabled, one `plan_update` and one confirmed `apply_update` completed with audit logs
- [ ] Rollback scripts/commands are ready
- [ ] Release notes include impact and fallback
- [ ] Cross-repo release manifest is updated/committed in the control repo (`releases/<version>.yaml`)
- [ ] The stable release gate was executed in `local` mode and `stable` mode for the candidate service
- [ ] The stable smoke endpoint returned a 2xx response for the service under release

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
