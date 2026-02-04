# console.svc.plus OAuth Integration Spec

## 1. UI Surfaces

### Login Page

- Buttons:
  - `Continue with GitHub`
  - `Continue with Google`
- Button action:
  - redirect to `accounts` start endpoint with `intent=login`

Example:

```text
https://accounts.svc.plus/oauth/github/start?intent=login&return_to=https%3A%2F%2Fconsole.svc.plus%2Fauth%2Fcallback
```

### Settings / Security Page

- Show identity status for `github`, `google`
- Show button by state:
  - unlinked => `Bind GitHub` / `Bind Google`
  - linked => `Unlink`
- Bind action:
  - redirect to `accounts` with `intent=bind`

## 2. Callback Handling

`GET /auth/callback`

- Read result from accounts redirect parameters (or cookie/session exchange)
- On success:
  - establish console session (cookie/JWT exchange)
  - redirect to intended page
- On failure:
  - map error code to localized message

Suggested error mapping:

- `OAUTH_STATE_INVALID` => "Login session expired, please retry"
- `OAUTH_IDENTITY_CONFLICT` => "This social account is already linked to another account"
- `OAUTH_EMAIL_CONFLICT` => "Email conflict, please use existing account login"

## 3. API Calls from Console

- `GET https://accounts.svc.plus/me/identities`
- `POST https://accounts.svc.plus/me/identities/:provider/unlink`

## 4. Client Feature Flags

- `auth.social.github.enabled`
- `auth.social.google.enabled`
- `auth.social.bind.enabled`

Rollout strategy:

1. enable `github` login only
2. enable `google` login
3. enable bind/unbind UI

## 5. QA Checklist

- [ ] Login success via GitHub
- [ ] Login success via Google
- [ ] Bind success when already logged in
- [ ] Conflict message shown when binding occupied identity
- [ ] Unlink works and UI state refreshes
- [ ] If last auth factor, unlink blocked with explicit message
- [ ] callback errors are user-readable and traceable by code
