# accounts.svc.plus OAuth & Identity Binding Spec

## 1. Data Model

### Table: `user_identities`

```sql
CREATE TABLE IF NOT EXISTS user_identities (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(32) NOT NULL,
  provider_user_id VARCHAR(191) NOT NULL,
  provider_login VARCHAR(191),
  email VARCHAR(320),
  email_verified BOOLEAN,
  access_token_encrypted TEXT,
  refresh_token_encrypted TEXT,
  token_expires_at TIMESTAMPTZ,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  raw_profile JSONB,
  UNIQUE(provider, provider_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_identities_user_id
  ON user_identities(user_id);

CREATE INDEX IF NOT EXISTS idx_user_identities_provider_user
  ON user_identities(provider, provider_user_id);
```

## 2. Environment Variables

- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`
- `GITHUB_CALLBACK_URL`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_CALLBACK_URL`
- `OAUTH_STATE_SIGNING_KEY`
- `OAUTH_ALLOW_EMAIL_AUTO_LINK` (`true|false`, default `false`)

## 3. API Contract

### 3.1 Start OAuth

`GET /oauth/:provider/start?intent=login|bind&return_to=<url>`

- `provider`: `github | google`
- `intent=login`: anonymous allowed
- `intent=bind`: requires authenticated session
- Returns: `302` redirect to provider auth URL

### 3.2 Callback

`GET /oauth/:provider/callback?code=...&state=...`

Behavior:

- validate `state`
- exchange `code` for tokens
- fetch provider profile
- route by `intent`

`intent=login`:

1. match `(provider, provider_user_id)` => login
2. if none:
   - if `OAUTH_ALLOW_EMAIL_AUTO_LINK=true` and unique email exists: link to existing user
   - else create user + identity
3. issue session/JWT
4. redirect `return_to` with success

`intent=bind`:

1. require current user
2. if identity belongs to another user => conflict error
3. else upsert identity to current user
4. redirect `return_to` with success

### 3.3 Unlink

`POST /me/identities/:provider/unlink`

- Requires authenticated user
- If this is last login method and no password set, return `409 CANNOT_UNLINK_LAST_FACTOR`
- Otherwise unlink identity

### 3.4 Identity List

`GET /me/identities`

Response:

```json
{
  "items": [
    {
      "provider": "github",
      "provider_login": "octocat",
      "linked_at": "2026-02-04T10:00:00Z"
    }
  ]
}
```

## 4. Error Codes

- `OAUTH_STATE_INVALID`
- `OAUTH_PROVIDER_EXCHANGE_FAILED`
- `OAUTH_PROVIDER_PROFILE_FAILED`
- `OAUTH_IDENTITY_CONFLICT`
- `OAUTH_EMAIL_CONFLICT`
- `CANNOT_UNLINK_LAST_FACTOR`

## 5. Security Requirements

- `state` must be signed and single-use (TTL <= 10 min)
- PKCE recommended for public clients
- Google `id_token` checks:
  - `iss` in `accounts.google.com` / `https://accounts.google.com`
  - `aud` equals configured `GOOGLE_CLIENT_ID`
  - `exp` not expired
  - `email_verified=true` for email-based linking
- Store refresh/access tokens encrypted at rest

## 6. Audit Logging

Audit events minimum:

- `oauth_login_succeeded`
- `oauth_login_failed`
- `oauth_bind_succeeded`
- `oauth_bind_failed`
- `oauth_unlink_succeeded`
- `oauth_unlink_failed`

Each event should include:

- `user_id` (if available)
- `provider`
- `provider_user_id` (masked)
- `ip`, `user_agent`
- `trace_id`
- `error_code` (on failure)
