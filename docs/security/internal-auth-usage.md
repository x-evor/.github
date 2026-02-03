# Internal Service Authentication Usage Guide

**Date**: 2026-01-29  
**Status**: Active  
**Related**: [Shared Token Authentication Design](./shared-token-auth-design.md) | [Service Chain Audit](./service-chain-auth-audit.md)

## Overview

This guide explains how to use the `INTERNAL_SERVICE_TOKEN` authentication system for secure service-to-service (M2M) communication in the Cloud-Neutral Toolkit ecosystem.

## Quick Start

### 1. Generate a Service Token

```bash
openssl rand -base64 32
```

Example output:
```
YOUR_GENERATED_TOKEN_HERE_BASE64_32_BYTES
```

### 2. Configure Environment Variable

Add to all backend services:

```env
INTERNAL_SERVICE_TOKEN=<your-generated-token-here>
```

**Critical**: The token MUST be identical across all services in the same environment.

### 3. Environment Separation

Use different tokens for different environments:

```bash
# Development
INTERNAL_SERVICE_TOKEN=<dev-token-here>

# Staging
INTERNAL_SERVICE_TOKEN=<staging-token-here>

# Production
INTERNAL_SERVICE_TOKEN=<production-token-here>
```

## Backend Services - Middleware Setup

### Go Services

**File**: `internal/auth/middleware.go`

```go
package auth

import (
    "os"
    "github.com/gin-gonic/gin"
)

// InternalAuthMiddleware validates internal service-to-service authentication
func InternalAuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        serviceToken := c.GetHeader("X-Service-Token")
        if serviceToken == "" {
            c.JSON(401, gin.H{"error": "missing service token"})
            c.Abort()
            return
        }

        expectedToken := os.Getenv("INTERNAL_SERVICE_TOKEN")
        if expectedToken == "" {
            c.JSON(500, gin.H{"error": "internal service token not configured"})
            c.Abort()
            return
        }

        if serviceToken != expectedToken {
            c.JSON(401, gin.H{"error": "invalid service token"})
            c.Abort()
            return
        }

        c.Next()
    }
}
```

**Usage in routes**:

```go
// Protected internal endpoint
router.GET("/internal/health", auth.InternalAuthMiddleware(), healthHandler)
```

### JavaScript/Node.js Services

**File**: `middleware/auth.js`

```javascript
function createInternalAuthMiddleware() {
  return function internalAuthMiddleware(req, res, next) {
    const serviceToken = req.headers['x-service-token'];
    
    if (!serviceToken) {
      return res.status(401).json({ error: 'missing service token' });
    }

    const expectedToken = process.env.INTERNAL_SERVICE_TOKEN;
    
    if (!expectedToken) {
      return res.status(500).json({ error: 'internal service token not configured' });
    }

    if (serviceToken !== expectedToken) {
      return res.status(401).json({ error: 'invalid service token' });
    }

    next();
  };
}

module.exports = { createInternalAuthMiddleware };
```

**Usage in Express**:

```javascript
const { createInternalAuthMiddleware } = require('./middleware/auth');

app.use('/api', createInternalAuthMiddleware());
```

## Frontend Services - Client Implementation

### Next.js API Routes

**Add to fetch requests**:

```typescript
const serviceToken = process.env.INTERNAL_SERVICE_TOKEN;

const response = await fetch('https://accounts.svc.plus/api/endpoint', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Service-Token': serviceToken || '',
  },
  body: JSON.stringify(data),
});
```

**Best Practice - Reusable Utility**:

```typescript
// server/internalServiceAuth.ts
export function buildInternalServiceHeaders(baseHeaders?: HeadersInit): Headers {
  const headers = new Headers(baseHeaders);
  const token = process.env.INTERNAL_SERVICE_TOKEN;
  
  if (token) {
    headers.set('X-Service-Token', token);
  }
  
  return headers;
}

// Usage in API routes
const headers = buildInternalServiceHeaders({
  'Content-Type': 'application/json'
});

const response = await fetch(url, { headers });
```

## Security Best Practices

### ✅ Do

- **Use HTTPS**: Always use HTTPS/TLS for all service-to-service communication
- **Rotate tokens**: Rotate tokens quarterly or when team members leave
- **Separate environments**: Use different tokens for dev/staging/prod
- **Store securely**: Use Cloud Run Secrets, AWS Secrets Manager, or equivalent
- **Monitor access**: Log authentication failures and investigate anomalies
- **Validate on every request**: Never skip authentication checks

### ❌ Don't

- **Never commit tokens**: Do not commit tokens to version control
- **No HTTP**: Never use plain HTTP in production
- **No shared dev tokens in prod**: Keep production tokens isolated
- **Don't log tokens**: Avoid logging the actual token value
- **No client-side exposure**: Never expose tokens to browser/client code

## Deployment Checklist

### Cloud Run Deployment

```bash
# Set secret via console or CLI
gcloud secrets create internal-service-token \
  --data-file=- <<< "YOUR_TOKEN_HERE"

# Grant service account access
gcloud secrets add-iam-policy-binding internal-service-token \
  --member="serviceAccount:SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

# Deploy with secret
gcloud run deploy SERVICE_NAME \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest
```

### Environment Variable Verification

```bash
# Check if token is configured (without revealing value)
if [ -z "$INTERNAL_SERVICE_TOKEN" ]; then
  echo "❌ INTERNAL_SERVICE_TOKEN not set"
else
  echo "✅ INTERNAL_SERVICE_TOKEN configured (length: ${#INTERNAL_SERVICE_TOKEN})"
fi
```

## Testing

### Test Authentication

```bash
# Without token (should fail with 401)
curl -X GET https://accounts.svc.plus/internal/health

# With invalid token (should fail with 401)
curl -X GET https://accounts.svc.plus/internal/health \
  -H "X-Service-Token: invalid_token"

# With correct token (should succeed)
curl -X GET https://accounts.svc.plus/internal/health \
  -H "X-Service-Token: $INTERNAL_SERVICE_TOKEN"
```

### Verify Service Chain

```bash
# Test complete flow through console → accounts
curl -X POST https://console.svc.plus/api/test-auth \
  -H "Authorization: Bearer YOUR_USER_TOKEN"

# Check logs for X-Service-Token presence
gcloud logging read "resource.type=cloud_run_revision AND X-Service-Token"
```

## Troubleshooting

### Error: "missing service token"

**Cause**: Client not sending `X-Service-Token` header

**Solution**: 
1. Verify frontend API route includes token in headers
2. Check `INTERNAL_SERVICE_TOKEN` is set in frontend service environment

### Error: "invalid service token"

**Cause**: Token mismatch between services

**Solution**:
1. Verify all services use the same token value
2. Check for extra whitespace or special characters
3. Ensure token is properly loaded from environment

### Error: "internal service token not configured"

**Cause**: Backend service missing `INTERNAL_SERVICE_TOKEN` environment variable

**Solution**:
1. Add environment variable to service configuration
2. Redeploy service
3. Verify using environment variable check script

## Token Rotation Procedure

### Steps

1. **Generate new token**:
   ```bash
   openssl rand -base64 32 > new_token.txt
   ```

2. **Update one service at a time**:
   - Update environment variable with new token
   - Deploy service
   - Verify health checks pass

3. **Monitor for errors**:
   - Check logs for authentication failures
   - Roll back if issues detected

4. **Complete rotation**:
   - Update all services
   - Delete old token from secrets manager
   - Update documentation

## Support

For questions or issues:
- GitHub Issues: https://github.com/cloud-neutral-toolkit/discussions
- Email: contact@svc.plus
