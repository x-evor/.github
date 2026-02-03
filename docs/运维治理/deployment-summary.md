# Service Authentication Deployment Summary

**Date**: 2026-01-29 23:05  
**Status**: ✅ Development Environment Configured  
**Token Generated**: See local `.env` files (not stored in git)

## ✅ Completed Configuration

### Environment Variables Set

All services have been configured with `INTERNAL_SERVICE_TOKEN`:

| Service | File | Status |
|---------|------|--------|
| console.svc.plus | `.env` | ✅ Configured |
| accounts.svc.plus | `.env` | ✅ Configured |
| rag-server.svc.plus | `.env` | ✅ Configured |
| page-reading-agent-backend | `.env` | ✅ Configured |
| page-reading-agent-dashboard | `.env.local` | ✅ Configured |

### Token Value

> **Note**: Token value is stored in local `.env` files. DO NOT commit to git.

```bash
INTERNAL_SERVICE_TOKEN=<stored-in-local-env-files>
```

## 🔧 Code Changes Applied

### Frontend API Routes Updated

1. **console.svc.plus/src/lib/apiProxy.ts**
   - Auto-injects X-Service-Token for all proxy routes
   
2. **console.svc.plus/src/app/api/askai/route.ts**
   - Added X-Service-Token to RAG server requests

3. **console.svc.plus/src/app/api/rag/query/route.ts**
   - Added X-Service-Token to RAG server requests

4. **console.svc.plus/src/app/api/users/route.ts**
   - Added X-Service-Token to backend API requests
   - Updated TypeScript type definition

5. **page-reading-agent-dashboard/app/api/run-task/route.ts**
   - Added X-Service-Token to backend requests

### Backend Middleware (Already Implemented)

- ✅ accounts.svc.plus - `InternalAuthMiddleware()` in Go
- ✅ rag-server.svc.plus - `InternalAuthMiddleware()` in Go
- ✅ page-reading-agent-backend - `internalAuthMiddleware()` in JavaScript

## 🧪 Local Testing

### Quick Verification

```bash
# Verify token is set in all services
for dir in console.svc.plus accounts.svc.plus rag-server.svc.plus page-reading-agent-backend; do
  echo "=== $dir ==="
  cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/$dir
  grep INTERNAL_SERVICE_TOKEN .env 2>/dev/null || grep INTERNAL_SERVICE_TOKEN .env.local 2>/dev/null || echo "❌ Not found"
done
```

### Start Services for Testing

```bash
# Terminal 1: Start accounts service
cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/accounts.svc.plus
make run

# Terminal 2: Start RAG server
cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/rag-server.svc.plus
make run

# Terminal 3: Start console frontend
cd /Users/shenlan/workspaces/Cloud-Neutral-Toolkit/console.svc.plus
npm run dev

# Terminal 4: Start page-reading-agent-backend
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/page-reading-agent-backend
node main.js
```

### Test Authentication Flow

```bash
# Test 1: Direct backend request without token (should fail)
curl -X GET http://localhost:8080/api/health \
  -H "Content-Type: application/json"

# Expected: 401 Unauthorized

# Test 2: With correct token (should succeed)
curl -X GET http://localhost:8080/api/health \
  -H "Content-Type: application/json" \
  -H "X-Service-Token: $INTERNAL_SERVICE_TOKEN"

# Expected: 200 OK

# Test 3: Console → Backend flow
# Navigate to http://localhost:3000 and test any feature that calls backend
# Monitor logs to verify X-Service-Token is being sent
```

## 🚀 Production Deployment Steps

### 1. Store Token in Cloud Run Secrets

```bash
# Create secret in Google Cloud (use your actual token)
cat .env | grep INTERNAL_SERVICE_TOKEN | cut -d'=' -f2 | \
gcloud secrets create internal-service-token \
  --data-file=- \
  --project=xzerolab-480008

# Verify secret created
gcloud secrets list --project=xzerolab-480008 | grep internal-service-token
```

### 2. Grant Service Accounts Access

```bash
# Get service account for each Cloud Run service
# Replace SERVICE_NAME with actual service name

for SERVICE in accounts-svc-plus rag-server-svc-plus console-svc-plus; do
  SA=$(gcloud run services describe $SERVICE \
    --region=asia-northeast1 \
    --format='value(spec.template.spec.serviceAccountName)')
  
  echo "Granting access to $SA for $SERVICE"
  
  gcloud secrets add-iam-policy-binding internal-service-token \
    --member="serviceAccount:$SA" \
    --role="roles/secretmanager.secretAccessor" \
    --project=xzerolab-480008
done
```

### 3. Update Cloud Run Services

```bash
# console.svc.plus
gcloud run services update console-svc-plus \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008

# accounts.svc.plus
gcloud run services update accounts-svc-plus \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008

# rag-server.svc.plus
gcloud run services update rag-server-svc-plus \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008

# page-reading-agent-backend
gcloud run services update page-reading-agent-backend \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008

# page-reading-agent-dashboard
gcloud run services update page-reading-agent-dashboard \
  --update-secrets=INTERNAL_SERVICE_TOKEN=internal-service-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008
```

### 4. Verify Deployment

```bash
# Check service status
gcloud run services list --project=xzerolab-480008

# Test endpoints
curl -X POST https://console.svc.plus/api/askai \
  -H "Authorization: Bearer YOUR_USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"test","history":[]}'

# Monitor logs for errors
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" \
  --limit=50 \
  --project=xzerolab-480008
```

## 📋 Security Checklist

- [x] Token generated with strong cryptography (openssl)
- [x] Token configured in all services
- [ ] Token stored in Cloud Run Secrets (production)
- [ ] Service accounts granted secret access
- [ ] All services using HTTPS/TLS in production
- [ ] PostgreSQL using stunnel TLS connections
- [ ] Monitoring configured for authentication failures
- [ ] Token rotation procedure documented

## 📚 Documentation

- [service-chain-auth-implementation.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/设计开发/service-chain-auth-implementation.md) - Implementation plan
- [internal-auth-usage.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/安全/internal-auth-usage.md) - Usage guide
- [service-chain-auth-audit.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/安全/service-chain-auth-audit.md) - Security audit
- [shared-token-auth-design.md](file:///Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/安全/shared-token-auth-design.md) - Design document

## ⚠️ Important Notes

1. **DO NOT commit .env files to git** - They now contain sensitive token
2. **Use different tokens for different environments** - This token is for development only
3. **Rotate tokens quarterly** - Follow the rotation procedure in internal-auth-usage.md
4. **Monitor authentication failures** - Set up alerts for 401 errors related to service tokens

## Next Steps

1. ✅ Local environment configured
2. ⏳ Test locally with all services running
3. ⏳ Deploy to staging with Cloud Run Secrets
4. ⏳ Verify service-to-service communication
5. ⏳ Deploy to production
6. ⏳ Monitor logs and metrics
