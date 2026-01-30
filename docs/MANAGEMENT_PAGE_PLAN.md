# Management Page Completion Implementation Plan

This plan outlines the steps to complete the functionality of the `/panel/management` page in `console.svc.plus`, ensuring all dashboard cards, charts, permission matrix, and user group management are operational.

## Proposed Changes

### [Backend] accounts.svc.plus

#### [MODIFY] [internal/store/store.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/store/store.go)
- Add `ListUsers(ctx context.Context) ([]User, error)` to the `Store` interface.
- Implement `ListUsers` in `memoryStore`.
- Ensure `CancelSubscription` is present in the `Store` interface.

#### [MODIFY] [internal/store/postgres.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/store/postgres.go)
- Implement `ListUsers` in `postgresStore` using a `SELECT` query on the `users` table.

#### [MODIFY] [api/api.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/api/api.go)
- Add `h.listUsers` handler: Fetches all users from the store and returns them as a sanitized list.
- Add `h.updateUserRole` handler: Updates a user's role and numeric level.
- Add `h.resetUserRole` handler: Resets a user's role to the default 'user'.
- Register routes:
    - `GET /api/users` -> `h.listUsers`
    - `POST /api/auth/admin/users/:userId/role` -> `h.updateUserRole`
    - `DELETE /api/auth/admin/users/:userId/role` -> `h.resetUserRole`

#### [MODIFY] [internal/auth/token_service.go](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus/internal/auth/token_service.go)
- Add `GeneratePublicToken(userID, email string, roles []string) string` to `TokenService` to support OAuth callback logic.

### [Frontend Proxy] console.svc.plus

#### [MODIFY] [src/app/api/users/route.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/api/users/route.ts)
- Update `SERVER_USERS_ENDPOINT` to point to `ACCOUNT_API_BASE` (the account service) instead of the general server API base.
- Ensure `Authorization` header with Bearer token is included in the proxy request.

## Verification Plan

### Automated Tests
- Run `go test ./internal/store/... ./api/...` in `accounts.svc.plus`.
- Verify all tests pass with exit code 0.

### Manual Verification
1. Navigate to `/panel/management` in the browser.
2. Verify that the "Overview" cards show actual numbers (if metrics provider is configured).
3. Verify that the "User Group" table lists all registered users.
4. Attempt to change a user's role and verify it persists in the database.
5. Verify the Permission Matrix can be saved.
