# Runbook: Sandbox Mode Setup & Agent Sync Stability

## Overvew
This runbook describes the configuration and troubleshooting of the **Sandbox Mode** feature and the resolution of persistent `500 Internal Server Error` issues during agent synchronization.

## 1. Sandbox Mode
Sandbox mode allows specific agent nodes to be "locked" to a canonical sandbox user (`Sandbox@svc.plus`). This is useful for testing infrastructure without affecting production user data.

### Configuration
1.  **Server Initialization**: On startup, the accounts service ensures the `Sandbox@svc.plus` user exists.
2.  **Node Binding**: Root administrators must bind an agent ID to Sandbox mode via the Admin Console.
    *   **Path**: `User Center` -> `Management` -> `Sandbox Node Binding`
    *   **API**: `POST /api/admin/sandbox/bind`
3.  **Synchronization**: When an agent marked as a "Sandbox Agent" requests its client list, the accounts server returns **only** the `Sandbox@svc.plus` credentials.

### Database Persistence
Bindings are stored in the `sandbox_bindings` table in the accounts database. This ensures that sandbox state persists across server restarts.

## 2. Agent Sync Stability
The synchronization between Agents (e.g., `agent.svc.plus`) and the Accounts Controller relies on several specific database columns in the `public.users` table.

### Required Schema
The following columns must exist for sync to succeed:
- `proxy_uuid` (UUID, non-null)
- `created_at` (TIMESTAMPTZ)
- `updated_at` (TIMESTAMPTZ)

### Automated Repair
If these columns are missing (causing `500` errors), the server attempts explicit `ALTER TABLE` operations during its initialization phase (`applyRBACSchema`).

## 3. Troubleshooting

### Symptom: `controller returned 500 Internal Server Error`
**Cause**: Usually missing columns in the `users` table or failure to list clients from the database.
**Check**:
1. Check accounts service logs for `failed to list clients from users table` or `failed to list clients from source`.
2. Ensure the latest commits (post-`33bd1b8b`) are deployed to the accounts service.
3. Verify that the agent is authenticated with a valid Bearer token.

### Symptom: Wildcard Agent appears in UI
**Cause**: The "Internal Agents (Shared Token)" wildcard (`ID: "*"`) was previously listed in the node selector.
**Fix**: Update to commit `3b818314` or later, which filters out the wildcard from the `/api/agent-server/v1/nodes` response.

### Symptom: Sandbox Node not receiving test user
**Check**:
1. Ensure the Node is correctly bound in the Admin Console.
2. Verify the `Sandbox@svc.plus` user is active and has a valid `proxy_uuid` generated.

## 4. Key References
- **Accounts Main**: `accounts.svc.plus/cmd/accountsvc/main.go`
- **Agent Registry**: `accounts.svc.plus/internal/agentserver/registry.go`
- **Admin Panel**: `console.svc.plus/src/modules/extensions/builtin/user-center/management/components/SandboxNodeBindingPanel.tsx`
