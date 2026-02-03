# OAuth2 Integration Implementation Plan

This plan outlines the steps to integrate GitHub and Google OAuth2 authentication into the `accounts.svc.plus` backend and `console.svc.plus` frontend, while removing legacy WeChat placeholders.

## Proposed Changes

### [Backend] accounts.svc.plus

#### [MODIFY] [config/config.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/config/config.go)
- Add `OAuth` struct to `Auth` config to hold GitHub and Google client IDs and secrets.
- Add `RedirectURL` for OAuth callbacks.

#### [NEW] [internal/auth/oauth.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/auth/oauth.go)
- Define `OAuthProvider` interface.
- Implement `GitHubProvider` and `GoogleProvider` structs.
- Add logic to exchange `code` for user profile (email, name, social ID).

#### [MODIFY] [api/api.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/api/api.go)
- Add `/api/auth/oauth/login/{provider}`: Redirects user to OAuth provider.
- Add `/api/auth/oauth/callback/{provider}`:
    - Verifies `state`.
    - Exchanges `code` for profile.
    - Checks if user exists by email or provider/socialID.
    - If not, auto-creates user (marking email as verified since it comes from trusted provider).
    - Generates JWT and redirects back to frontend with a `public_token`.

#### [MODIFY] [internal/store/store.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/store/store.go) & [postgres.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/store/postgres.go)
- Ensure identification by provider/externalID is supported (already exists in `identities` table but might need helpers).

---

### [Frontend] console.svc.plus

#### [MODIFY] [src/app/(auth)/login/LoginContent.tsx](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/(auth)/login/LoginContent.tsx)
- Enable social login buttons (`socialButtonsDisabled = false`).
- Add Google login button.
- Update `githubAuthUrl` and `googleAuthUrl` to point to the backend OAuth login endpoints.
- [DELETE] Remove `WeChatIcon` and WeChat social button.

#### [MODIFY] [src/app/(auth)/register/RegisterContent.tsx](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/(auth)/register/RegisterContent.tsx)
- Set `isSocialAuthVisible = true`.
- Add Google login button.
- [DELETE] Remove `WeChatIcon` and WeChat social button.

#### [DELETE] [src/components/icons/WeChatIcon.tsx](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/components/icons/WeChatIcon.tsx)
- Remove the WeChat icon component as it is no longer needed.

## Verification Plan

### Automated Tests
- No existing OAuth2 automated tests found.
- I will add a mock OAuth2 provider in backend tests to verify the registration/login logic through the callback.
- Run `go test ./api/...` in `accounts.svc.plus`.

### Manual Verification
1. Click "Login with GitHub" on the login page.
2. Verify redirection to GitHub (will require real ClientID/Secret or mock).
3. Verify that after callback, a new user is created in the database and the system logs in automatically.
4. Verify that Google login works similarly.
5. Verify that email verification is considered "complete" for OAuth users.
