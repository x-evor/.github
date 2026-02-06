# Runbook: Login Failure - Stunnel Connection Issues

**Date**: 2026-02-06  
**Severity**: P1 (Service Outage)  
**Status**: Diagnosed - Awaiting Server Fix  
**Services Affected**: console.svc.plus login, accounts.svc.plus API

---

## Incident Summary

Users unable to log in to https://console.svc.plus/login with 500 errors. Root cause identified as stunnel server not responding on postgresql.svc.plus:443.

## Architecture Overview

### System Components

```
Frontend (Vercel)          API (Cloud Run)              Database (VM)
─────────────────          ───────────────              ─────────────

console.svc.plus    →    accounts-svc-plus      →    postgresql.svc.plus
                          ┌──────────────┐            ┌──────────────┐
                          │ Main App     │            │ stunnel:443  │
                          │ Container    │            │      ↓       │
                          │      ↓       │            │ postgres:5432│
                          │ stunnel      │            └──────────────┘
                          │ client       │
                          │ 127.0.0.1    │
                          │ :15432       │
                          └──────────────┘
```

### Stunnel TLS Tunnel Flow

1. **Application** connects to `127.0.0.1:15432` (local stunnel client)
2. **Stunnel client** (sidecar) creates TLS connection to `postgresql.svc.plus:443`
3. **Stunnel server** (on postgresql.svc.plus) listens on port 443
4. **Stunnel server** forwards decrypted traffic to `postgres:5432`
5. **PostgreSQL** processes the query and returns data

## Root Cause

**Stunnel server on postgresql.svc.plus is not running or not accessible on port 443.**

### Evidence

```
# Cloud Run logs
failed to connect to `user=postgres database=account`: 127.0.0.1:15432 (127.0.0.1): 
failed to receive message: timeout: context deadline exceeded

s_connect: s_poll_wait 34.85.14.134:443: TIMEOUTconnect exceeded
```

### Verified Configuration

Cloud Run configuration is **correct**:
- ✅ `DB_HOST=127.0.0.1`
- ✅ `DB_PORT=15432`
- ✅ Stunnel sidecar container running
- ✅ stunnel-config secret exists
- ✅ CORS and authentication properly configured

## Diagnostic Steps

### 1. Quick Check from Client Side

```bash
# Test if postgresql.svc.plus:443 is reachable
nc -zv postgresql.svc.plus 443

# Test TLS handshake
openssl s_client -connect postgresql.svc.plus:443
```

**Expected**: Connection successful  
**Actual**: Connection timeout

### 2. Server-Side Diagnosis

SSH to the database server:

```bash
ssh root@postgresql.svc.plus
```

Run the diagnostic script:

```bash
cd ~/postgresql.svc.plus
bash scripts/diagnose_stunnel.sh
```

The script checks:
- Docker container status
- Port 443 listening status
- Firewall rules
- Stunnel logs
- Docker Compose services

### 3. Common Issues

| Issue | Check | Fix |
|-------|-------|-----|
| Stunnel not running | `docker ps \| grep stunnel` | Restart docker-compose |
| Port 443 not listening | `ss -tlnp \| grep :443` | Check stunnel config |
| Firewall blocking | `sudo ufw status` | Allow port 443 |
| Certificate issues | `docker logs <stunnel-id>` | Regenerate certs |

## Resolution Steps

### Option 1: Restart Stunnel Service

```bash
cd ~/postgresql.svc.plus/deploy/docker

# Check current status
docker compose -f docker-compose.yml -f docker-compose.tunnel.yml ps

# Restart stunnel
docker compose -f docker-compose.yml -f docker-compose.tunnel.yml restart stunnel

# Or restart all services
docker compose -f docker-compose.yml -f docker-compose.tunnel.yml down
docker compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d
```

### Option 2: Fix Firewall

```bash
# Ubuntu/Debian
sudo ufw allow 443/tcp
sudo ufw reload

# CentOS/Rocky Linux
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

### Option 3: Reinitialize Server

If stunnel was never properly set up:

```bash
curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/postgresql.svc.plus/main/scripts/init_vhost.sh \
  | bash -s -- 17 postgresql.svc.plus
```

This will:
- Install PostgreSQL 17
- Configure stunnel server on port 443
- Set up Let's Encrypt TLS certificates
- Start all services

## Verification

After applying fixes:

### 1. Verify Stunnel Server

```bash
# Check stunnel is running
docker ps | grep stunnel

# Check port 443 is listening
ss -tlnp | grep :443

# Check stunnel logs for errors
docker logs <stunnel-container-id>
```

### 2. Test Connection from Client

```bash
# From any machine with network access
nc -zv postgresql.svc.plus 443

# Should output: Connection to postgresql.svc.plus 443 port [tcp/https] succeeded!
```

### 3. Test Login Flow

1. Navigate to https://console.svc.plus/login
2. Enter credentials: `admin@svc.plus` / `pZ6MlUthGd`
3. Verify successful login without 500 errors
4. Check Cloud Run logs for successful database connections

## Prevention

### Monitoring

Add monitoring for:
- Port 443 availability on postgresql.svc.plus
- Stunnel process health
- Database connection success rate from Cloud Run

### Alerts

Set up alerts for:
- Stunnel container down
- Port 443 not responding
- High database connection error rate

### Documentation

Ensure all team members know:
- The stunnel architecture
- How to diagnose connection issues
- Where to find diagnostic scripts

## Related Files

- **Diagnostic Script**: `/Users/shenlan/workspaces/cloud-neutral-toolkit/postgresql.svc.plus/scripts/diagnose_stunnel.sh`
- **Init Script**: `https://github.com/cloud-neutral-toolkit/postgresql.svc.plus/blob/main/scripts/init_vhost.sh`
- **Cloud Run Config**: `/Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus/deploy/gcp/cloud-run/service.yaml`
- **Stunnel Client Config**: `/Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus/deploy/gcp/cloud-run/stunnel.conf`

## Lessons Learned

1. **Architecture Complexity**: The stunnel tunnel architecture is not obvious from logs alone
2. **Multi-Layer Debugging**: Issue required checking both client (Cloud Run) and server (VM) sides
3. **Documentation Gap**: Stunnel architecture was not well documented in runbooks
4. **Monitoring Gap**: No alerts for stunnel server health

## Action Items

- [ ] Add stunnel health monitoring
- [ ] Create alerts for port 443 availability
- [ ] Document stunnel architecture in team wiki
- [ ] Add automated stunnel restart on failure
- [ ] Consider Cloud SQL as alternative to reduce complexity

## References

- **Investigation Details**: See artifact `implementation_plan.md`
- **Walkthrough**: See artifact `walkthrough.md`
- **PostgreSQL Setup**: https://github.com/cloud-neutral-toolkit/postgresql.svc.plus
- **Cloud Run Docs**: https://cloud.google.com/run/docs/configuring/containers
