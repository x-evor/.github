# OAuth Social Login Rollout Plan (accounts + console)

## Scope

- Repositories:
  - `accounts.svc.plus` (auth center)
  - `console.svc.plus` (business frontend)
- Providers:
  - GitHub OAuth
  - Google OAuth
- Scenarios:
  - Login/Register (`intent=login`)
  - Bind/Unbind (`intent=bind`, `POST unlink`)

## Architecture Boundary

- `accounts.svc.plus` is the **single auth authority**:
  - OAuth start/callback
  - identity binding and conflict handling
  - session/JWT issuance
- `console.svc.plus` is **consumer**:
  - redirects to accounts for social login
  - receives callback result and establishes app session
  - shows bind status and triggers bind/unbind

## Rollout Phases

1. Accounts: GitHub login-only
2. Accounts: Google login-only
3. Accounts: bind/unbind support
4. Console: login entry + callback handling + settings binding UI

## Deliverables

- Data model migration (`user_identities`)
- OAuth endpoints contract and error model
- Security controls (`state`, optional PKCE, token validations)
- Audit logs for login/bind/unbind lifecycle
- Console integration pages/components

## Milestones & Acceptance

### M1: Accounts GitHub Login

- [ ] `/oauth/github/start?intent=login`
- [ ] `/oauth/github/callback`
- [ ] user creation/login via provider identity
- [ ] audit log generated

### M2: Accounts Google Login

- [ ] `/oauth/google/start?intent=login`
- [ ] `/oauth/google/callback`
- [ ] `id_token` validation (`iss/aud/exp/email_verified`)
- [ ] audit log generated

### M3: Accounts Bind/Unbind

- [ ] `intent=bind` requires authenticated user
- [ ] conflict protection (identity already linked to another user)
- [ ] `POST /me/identities/:provider/unlink`
- [ ] audited bind/unbind events

### M4: Console Integration

- [ ] login page: GitHub/Google buttons
- [ ] settings page: bind status + bind/unbind actions
- [ ] callback handling for login/bind result
- [ ] user-facing error rendering based on error code

## Risks / Notes

- Existing local-account duplicates by email must be policy-driven (strict/manual merge/auto merge).
- Google workspace-restricted or unverified apps may block login in production.
- Redirect URI misconfiguration is the most common launch blocker; verify env parity across dev/stage/prod.

## References

- `docs/features/accounts-oauth-binding-spec.md`
- `docs/features/console-oauth-integration-spec.md`
