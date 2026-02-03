# Shared Token Authentication Design

**Date**: 2026-01-29  
**Status**: Implemented  
**Author**: Cloud-Neutral Toolkit Team

## Goal
Implement a secure, simple "Shared Token" mechanism for inter-service communication (M2M) while maintaining UUID+Email for user identification.

## Context
- **Services:** `console.svc.plus`, `accounts.svc.plus`, `rag-server.svc.plus`, `moltbot.svc.plus`, `page-reading-agent-backend`
- **Requirement:** Services authenticate via a shared token. Users authenticate via standard mechanisms (UUID/Email).

## Solution: Shared Secret (API Key)
We use a high-entropy static token (`INTERNAL_SERVICE_TOKEN`) shared across trusted internal services via environment variables.

### Environment Configuration
All services add:
```env
INTERNAL_SERVICE_TOKEN=sk_live_internal_secret_example_value
```

### Middleware Implementation
Create `InternalAuthMiddleware` that:
1. Checks for header `X-Service-Token`
2. Validates it against `os.Getenv("INTERNAL_SERVICE_TOKEN")`
3. If valid:
    - Sets context: `userID="system"`, `email="internal@system.service"`, `roles=["internal_service"]`

### Client Implementation
Internal API clients append `X-Service-Token` header to downstream requests:
```javascript
fetch('https://accounts.svc.plus/api/endpoint', {
    headers: {
        'X-Service-Token': process.env.INTERNAL_SERVICE_TOKEN
    }
})
```

## Implementation Status

### ✅ accounts.svc.plus
- **File**: `internal/auth/middleware.go`
- **Function**: `InternalAuthMiddleware()`
- **Language**: Go

### ✅ rag-server.svc.plus
- **File**: `internal/auth/middleware.go`
- **Function**: `InternalAuthMiddleware()`
- **Language**: Go

### ✅ page-reading-agent-backend
- **File**: `middleware/auth.js`
- **Function**: `createInternalAuthMiddleware()`
- **Language**: JavaScript/Node.js

### ⚠️ moltbot.svc.plus
- Uses separate hook token system
- Consider migrating to `INTERNAL_SERVICE_TOKEN` for consistency

## Security Requirements

### 🔒 HTTPS/TLS Mandatory
**ALL services MUST use HTTPS/TLS** to protect token in transit:
- ✅ `https://accounts.svc.plus`
- ✅ `https://rag-server.svc.plus`
- ✅ `https://moltbot.svc.plus`
- ✅ `https://page-reading-agent-backend.svc.plus`
- ❌ **NEVER** use plain HTTP for production

### Token Management
- **Generate**: `openssl rand -base64 32`
- **Rotate**: Quarterly
- **Storage**: Cloud Run Secrets, environment variables
- **Separation**: Different tokens for dev/staging/prod

## Verification
```bash
# Test with curl
curl -X GET https://accounts.svc.plus/internal/health \
  -H "X-Service-Token: sk_live_your_token_here"
```

## Related Documents
- [Service Chain Authentication Audit](./service-chain-auth-audit.md)
- [Internal Auth Usage Guide](./internal-auth-usage.md)
