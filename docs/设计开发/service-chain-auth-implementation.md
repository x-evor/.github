# Service Chain Authentication Implementation Plan

## Goal
Complete the shared token authentication system across all backend services by updating frontend API routes to send the `X-Service-Token` header to secure service-to-service communication.

## Background
Based on [service-chain-auth-audit.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/安全/service-chain-auth-audit.md) and [shared-token-auth-design.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/安全/shared-token-auth-design.md), backend services already have `InternalAuthMiddleware()` implemented:

- ✅ `accounts.svc.plus` - Go middleware in place
- ✅ `rag-server.svc.plus` - Go middleware in place  
- ✅ `page-reading-agent-backend` - JavaScript middleware in place

**Remaining work**: Update frontend API routes to include `X-Service-Token` header when calling backend services.

## User Review Required

> [!WARNING]
> **Environment Variable Required**
> All services must have `INTERNAL_SERVICE_TOKEN` environment variable configured before deployment. Use `openssl rand -base64 32` to generate a secure token.

> [!IMPORTANT]
> **HTTPS/TLS Mandatory**
> All services MUST use HTTPS in production to protect the token in transit. Never use plain HTTP for inter-service communication.

## Proposed Changes

### console.svc.plus - Frontend API Routes

#### [MODIFY] [apiProxy.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/lib/apiProxy.ts)
**Purpose**: Add `X-Service-Token` to forwarded headers in the proxy utility

**Changes**:
1. Add `x-service-token` to `DEFAULT_FORWARD_HEADERS` array
2. Update `buildForwardHeaders()` to automatically include service token from environment
3. Add helper to read `INTERNAL_SERVICE_TOKEN` environment variable

**Impact**: All proxy routes using `createUpstreamProxyHandler()` will automatically forward the token:
- `/app/api/agent/[...segments]/route.ts`
- `/app/api/task/[...segments]/route.ts`

---

#### [MODIFY] [askai/route.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/api/askai/route.ts)
**Purpose**: Add service token when calling RAG server

**Changes**:
1. Update `buildForwardHeaders()` to include `X-Service-Token` header
2. Read token from `process.env.INTERNAL_SERVICE_TOKEN`

---

#### [MODIFY] [rag/query/route.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/api/rag/query/route.ts)
**Purpose**: Add service token when calling RAG server

**Changes**:
1. Update `buildForwardHeaders()` to include `X-Service-Token` header
2. Read token from `process.env.INTERNAL_SERVICE_TOKEN`

---

#### [MODIFY] [users/route.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/app/api/users/route.ts)
**Purpose**: Add service token when calling backend API

**Changes**:
1. Update `buildForwardHeaders()` to include `X-Service-Token` header
2. Read token from `process.env.INTERNAL_SERVICE_TOKEN`

---

### page-reading-agent-dashboard - Frontend API Route

#### [MODIFY] [run-task/route.ts](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/page-reading-agent-dashboard/app/api/run-task/route.ts)
**Purpose**: Add service token when calling page-reading-agent-backend

**Changes**:
1. Add `X-Service-Token` header to fetch request
2. Read token from `process.env.INTERNAL_SERVICE_TOKEN`

---

### console.svc.plus - Shared Utility (Optional Enhancement)

#### [NEW] [server/internalServiceAuth.ts](file:///Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus/src/server/internalServiceAuth.ts)
**Purpose**: Create reusable utility for service token management

**Functions**:
- `getInternalServiceToken()`: Read token from environment
- `buildInternalServiceHeaders()`: Create headers with service token
- `validateServiceTokenConfigured()`: Check if token is configured

**Benefit**: Reduces code duplication across API routes

## Verification Plan

### Automated Tests

#### 1. Test Service Token Authentication
```bash
# Navigate to console.svc.plus
cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus

# Set test environment variable
export INTERNAL_SERVICE_TOKEN="test_token_for_verification"

# Run development server
npm run dev

# In another terminal, test API endpoints with curl
curl -X POST http://localhost:3000/api/askai \
  -H "Content-Type: application/json" \
  -d '{"question":"test","history":[]}'

# Check server logs to verify X-Service-Token is being sent
```

#### 2. Verify Backend Services Reject Unauthorized Requests
```bash
# Test accounts.svc.plus directly without token (should fail with 401)
curl -X GET https://accounts.svc.plus/api/internal/health

# Test with invalid token (should fail with 401)
curl -X GET https://accounts.svc.plus/api/internal/health \
  -H "X-Service-Token: invalid_token"

# Test with correct token (should succeed)
curl -X GET https://accounts.svc.plus/api/internal/health \
  -H "X-Service-Token: $INTERNAL_SERVICE_TOKEN"
```

#### 3. Integration Testing
```bash
# Test complete service chain through console frontend
cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus

# Run integration tests if they exist
npm test -- --grep "service.*auth"
```

### Manual Verification

#### Test 1: RAG Query Flow
1. Open browser to console.svc.plus
2. Navigate to RAG/Ask AI interface
3. Submit a query
4. **Expected**: Query succeeds and returns response
5. **Check server logs**: Verify `X-Service-Token` is in request headers

#### Test 2: User Management Flow
1. Log in as admin user
2. Navigate to user management page
3. Load user list
4. **Expected**: User list loads successfully
5. **Check backend logs**: Verify request has `X-Service-Token`

#### Test 3: Page Reading Agent
1. Open page-reading-agent-dashboard
2. Submit a task to the agent
3. **Expected**: Task executes successfully
4. **Check backend logs**: Verify token authentication

### Environment Configuration Verification

Create deployment checklist:
- [ ] `console.svc.plus` has `INTERNAL_SERVICE_TOKEN` env var
- [ ] `accounts.svc.plus` has `INTERNAL_SERVICE_TOKEN` env var
- [ ] `rag-server.svc.plus` has `INTERNAL_SERVICE_TOKEN` env var
- [ ] `page-reading-agent-backend` has `INTERNAL_SERVICE_TOKEN` env var
- [ ] `page-reading-agent-dashboard` has `INTERNAL_SERVICE_TOKEN` env var
- [ ] All tokens match across all services
- [ ] All services use HTTPS in production
- [ ] `postgresql.svc.plus` uses stunnel TLS for secure connections

### Monitoring

After deployment, monitor Cloud Run logs:
```bash
# Check for authentication failures
gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.error=~'service token'" --limit 50

# Verify successful requests
gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.message=~'internal_service'" --limit 50
```
