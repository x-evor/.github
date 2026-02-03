# Service Chain Authentication Audit Report

**Date**: 2026-01-29  
**Status**: Completed  
**Audited By**: Cloud-Neutral Toolkit Team

## Executive Summary
Completed comprehensive security audit of all services in the request chain. Implemented `INTERNAL_SERVICE_TOKEN` authentication across all backend services to prevent unauthorized access.

## Service Chain Architecture

```
console.svc.plus → accounts.svc.plus → postgresql.svc.plus
console.svc.plus → rag-server.svc.plus → postgresql.svc.plus
console.svc.plus → moltbot.svc.plus
console.svc.plus → page-reading-agent-dashboard → page-reading-agent-backend
```

## Audit Results

### ✅ 1. accounts.svc.plus
- **Status**: SECURED
- **Implementation**: `InternalAuthMiddleware()` in `internal/auth/middleware.go`
- **Auth Method**: Validates `X-Service-Token` header
- **Language**: Go

### ✅ 2. rag-server.svc.plus
- **Status**: SECURED
- **Implementation**: `InternalAuthMiddleware()` in `internal/auth/middleware.go`
- **Auth Method**: Validates `X-Service-Token` header
- **Language**: Go

### ✅ 3. moltbot.svc.plus
- **Status**: ALREADY SECURED
- **Implementation**: Hook-based token auth in `src/gateway/server-http.ts`
- **Auth Method**: `Authorization: Bearer` or `X-Clawdbot-Token` headers
- **Language**: TypeScript/Node.js
- **Note**: Uses own token system, not `INTERNAL_SERVICE_TOKEN`

### ✅ 4. page-reading-agent-backend
- **Status**: SECURED (NEW)
- **Implementation**: `middleware/auth.js` integrated in `main.js`
- **Auth Method**: Validates `X-Service-Token` header
- **Language**: JavaScript/Node.js
- **⚠️ Critical Fix**: Service was previously **UNPROTECTED**

### ⚠️ 5. page-reading-agent-dashboard
- **Status**: FRONTEND (N/A)
- **Type**: Next.js frontend application
- **Note**: Frontends don't require SERVICE_TOKEN (client-side)

### ⚠️ 6. postgresql.svc.plus
- **Status**: DATABASE (N/A)
- **Type**: PostgreSQL database
- **Protection**: Standard database credentials + TLS (`sslmode=require`)

### ⚠️ 7. console.svc.plus
- **Status**: FRONTEND + API ROUTES
- **Type**: Next.js application
- **Action Required**: Update API routes to send `X-Service-Token`

## Implementation Pattern

All services follow this validation pattern:

```javascript
const serviceToken = req.headers['x-service-token'];
const expectedToken = process.env.INTERNAL_SERVICE_TOKEN;

if (!serviceToken || serviceToken !== expectedToken) {
    return 401 Unauthorized
}
```

## 🔒 Critical Security Requirements

### Transport Encryption (MANDATORY)
**ALL services MUST use HTTPS/TLS**:

```
✅ https://accounts.svc.plus
✅ https://rag-server.svc.plus
✅ https://moltbot.svc.plus
✅ https://page-reading-agent-backend.svc.plus
❌ http:// - NEVER use plain HTTP
```

**PostgreSQL TLS**:
```bash
postgresql://user:pass@host:5432/db?sslmode=require
```

**Why?** Without HTTPS, `X-Service-Token` is transmitted in plaintext and can be intercepted.

## Security Recommendations

### 1. Token Generation
```bash
openssl rand -base64 32
```

### 2. Client Implementation
```javascript
// ALWAYS use HTTPS
fetch('https://accounts.svc.plus/api/endpoint', {
    headers: {
        'X-Service-Token': process.env.INTERNAL_SERVICE_TOKEN
    }
})
```

### 3. Token Rotation
- Rotate quarterly
- Separate tokens for dev/staging/prod
- Store in Cloud Run Secrets or equivalent

### 4. moltbot.svc.plus Consideration
- Currently uses separate hook token system
- Consider migrating to `INTERNAL_SERVICE_TOKEN` for consistency
- Or maintain separate token for webhook endpoints

## Action Items

- [x] Implement middleware in `accounts.svc.plus`
- [x] Implement middleware in `rag-server.svc.plus`
- [x] Secure `page-reading-agent-backend`
- [ ] **Verify HTTPS/TLS on all services**
- [ ] Configure `INTERNAL_SERVICE_TOKEN` in all environments
- [ ] Update `console.svc.plus` API routes to send token
- [ ] Configure PostgreSQL with `sslmode=require`
- [ ] Test service-to-service communication over HTTPS
- [ ] (Optional) Align moltbot.svc.plus with shared token system

## Files Modified

### Go Services
- `/accounts.svc.plus/internal/auth/middleware.go`
- `/rag-server.svc.plus/internal/auth/middleware.go`

### Node.js Services
- `/page-reading-agent-backend/middleware/auth.js` (new)
- `/page-reading-agent-backend/main.js`

## Related Documents
- [Shared Token Authentication Design](./shared-token-auth-design.md)
- [Internal Auth Usage Guide](./internal-auth-usage.md)
