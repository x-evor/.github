---
title: "OpenClaw Deployment Runbook"
summary: "Branch rebuild summary plus production runbook for Cloud Run plus GCS volume and single host Caddy plus Docker plus JuiceFS"
read_when:
  - You need a clean deployment baseline for openclawbot-svc-plus
  - You are choosing between Cloud Run on demand and a 7x24 single host deployment
  - You need a verification and rollback checklist for Caddy plus Docker plus JuiceFS
---

# OpenClaw Deployment Runbook

This runbook documents a minimal change deployment baseline for two targets:

- Cloud Run + GCS volume (on demand scaling)
- Single host Caddy + Docker + JuiceFS (7x24 runtime)

It also captures the branch rebuild summary and the exact configuration contract used by `openclawbot-svc-plus`.

For a multi-gateway deployment that keeps node configs independent while sharing memory and centralizing remote ingress in Kong, see [OpenClaw Multi-Gateway Architecture](multi-gateway-architecture.md).
For a Kong route and upstream sample, see [Kong Routing Draft](kong-routing.md).

## Scope and Targets

- Service name: `openclawbot-svc-plus`
- Region: `asia-northeast1`
- Bucket name: `openclawbot-data`
- State mount path: `/data`
- Shared memory path: `/data/memory`
- Required secrets:
  - `internal-service-token` for `OPENCLAW_GATEWAY_TOKEN`
  - `zai-api-key` for `Z_AI_API_KEY`

## Branch Rebuild Summary

Branch: `feat/cloud-run-deployment`

- Kept diff small and focused on deployment and runtime compatibility.
- Added Cloud Run compatible container flow and deployment wiring.
- Switched state and config to `OPENCLAW_STATE_DIR` and `OPENCLAW_CONFIG_PATH` instead of hardcoded paths.
- Kept Cloud Run on GCS volume and moved self-hosted shared mounts to JuiceFS.
- Kept desktop side compatibility updates for multi terminal bundle separation and UI assets.

## Shared Configuration Contract

These keys are common to both deployment modes:

- `OPENCLAW_STATE_DIR=/data`
- `OPENCLAW_CONFIG_PATH=/data/openclaw.json`
- `OPENCLAW_GATEWAY_TOKEN` from Secret Manager or local `.env`
- `Z_AI_API_KEY` from Secret Manager or local `.env`

Control UI origin policy:

- Requested Cloud Run profile can use `OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=*`.
- For non loopback single host exposure, explicit origins are safer and reduce startup failures.
- Recommended value on single host: `https://openclaw.svc.plus`.

## Path A Cloud Run Plus GCS

Authoritative service spec: `deploy/gcp/cloud-run/service.yaml`

### Required Cloud Run Settings

- `metadata.name`: `openclawbot-svc-plus`
- Region label: `asia-northeast1`
- `serviceAccountName`: project service account with GCS and Secret Manager access
- GCS volume via CSI:
  - driver: `gcsfuse.run.googleapis.com`
  - bucket: `openclawbot-data`
  - mount path: `/data`
- Env bindings:
  - `OPENCLAW_STATE_DIR=/data`
  - `OPENCLAW_CONFIG_PATH=/data/openclaw.json`
  - `OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=*`
- Secret bindings:
  - `OPENCLAW_GATEWAY_TOKEN <- internal-service-token:latest`
  - `Z_AI_API_KEY <- zai-api-key:latest`

### Deploy

Use either Cloud Build or direct replace:

```bash
gcloud builds submit --config cloudbuild.yaml .
```

```bash
gcloud run services replace deploy/gcp/cloud-run/service.yaml \
  --region=asia-northeast1
```

### Verify

```bash
gcloud run services describe openclawbot-svc-plus \
  --region=asia-northeast1 \
  --format='value(status.url,spec.template.spec.serviceAccountName)'
```

```bash
gcloud run revisions list \
  --service=openclawbot-svc-plus \
  --region=asia-northeast1
```

```bash
gcloud run services logs read openclawbot-svc-plus \
  --region=asia-northeast1 \
  --limit=200
```

Validation goals:

- New revision is serving 100 percent traffic.
- Secret references resolved without permission errors.
- `/data` mount is readable and writable by the runtime user.

## Path B Single Host Caddy Plus Docker Plus JuiceFS

This path is for persistent runtime on a host like `root@1.15.155.245`.

### Baseline Topology

- Caddy is public ingress on `80` and `443`.
- OpenClaw container listens on `127.0.0.1:18789`.
- Caddy reverse proxies to `127.0.0.1:18789`.
- JuiceFS is mounted to `/data`.
- JuiceFS metadata lives in PostgreSQL.
- GCS remains the object storage backend.
- Container mounts host `/data` as a volume.

### Step 1 Mount JuiceFS to `/data`

Example systemd mount service:

```ini
[Unit]
Description=Mount OpenClaw JuiceFS to /data
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/root/.env
ExecStart=/bin/bash -lc 'exec /usr/local/bin/juicefs mount --cache-dir "$JUICEFS_CACHE_DIR" --cache-size "$JUICEFS_CACHE_SIZE" --writeback "$JUICEFS_META_URL" /data'
ExecStop=/bin/bash -lc 'exec /usr/local/bin/juicefs umount /data || true'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Verification:

```bash
mount | grep /data
ls -la /data
test -f /data/openclaw.json
```

Required env in `/root/.env`:

- `JUICEFS_META_URL=postgres://openclaw@pg.internal:5432/openclawfs?sslmode=disable`
- `META_PASSWORD=<postgres-password>`
- `GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcp/openclaw-sa.json`
- `JUICEFS_CACHE_DIR=/var/cache/juicefs/openclaw`
- `JUICEFS_CACHE_SIZE=1024`

### Step 2 Local Secret File with Minimal Permission

Store runtime secrets in `/root/.env`:

- `OPENCLAW_GATEWAY_TOKEN=<token>`
- `Z_AI_API_KEY=<api-key>`

Permission baseline:

```bash
chown root:root /root/.env
chmod 600 /root/.env
```

### Step 3 Run OpenClaw in Docker with `/data` Volume

Use a systemd service and pin port mapping:

- `-p 127.0.0.1:18789:18789`
- `-v /data:/data`
- `--env-file /root/.env`
- `-e OPENCLAW_STATE_DIR=/data`
- `-e OPENCLAW_CONFIG_PATH=/data/openclaw.json`

Recommended explicit origin for non loopback bind:

- `-e OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=https://openclaw.svc.plus`

### Step 4 Caddy as Ingress with Auto TLS

Minimal Caddy pattern:

```caddyfile
{
  acme_ca https://acme-v02.api.letsencrypt.org/directory
}

openclaw.svc.plus {
  reverse_proxy 127.0.0.1:18789 {
    header_up Authorization "Bearer {$OPENCLAW_GATEWAY_TOKEN}"
    flush_interval -1
  }
}
```

Load token into Caddy with an environment file and do not hardcode secrets in `Caddyfile`.

### Step 5 Verify End to End

```bash
systemctl status openclawbot-svc-plus --no-pager
docker ps --filter name=openclawbot-svc-plus
curl -sSI http://127.0.0.1:18789
curl -skI https://openclaw.svc.plus
journalctl -u caddy -n 200 --no-pager
```

Expected:

- Docker container is running and transitions to `healthy`.
- HTTPS endpoint returns `200`.
- No recurring startup error about `gateway.controlUi.allowedOrigins`.

## Troubleshooting and Fix Patterns

### `non-loopback Control UI requires gateway.controlUi.allowedOrigins`

Root cause:

- Gateway binds non loopback without explicit allowed origins.

Fix:

- Set `gateway.controlUi.allowedOrigins` in `/data/openclaw.json`.
- Or set env `OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=https://openclaw.svc.plus`.
- Restart service and verify logs since current activation timestamp.

### Caddy ACME `connection refused` on `80` or `443`

Root cause candidates:

- Legacy DNAT rules hijack `80` or `443`.
- Leftover `KUBE-*` iptables chains from k3s block local dst type traffic.
- Caddy not actually listening on public interfaces.

Fix sequence:

- Remove stale DNAT rules for `80` and `443`.
- Disable obsolete DNAT helper services.
- Remove leftover k3s network artifacts if host no longer uses k3s.
- Recheck `ss -ltnp` for listeners on `:80` and `:443`.

### Caddy `502` with `connection reset by peer`

Interpretation:

- Usually transient during upstream restart or warmup.

Action:

- Confirm whether errors continue after service becomes `healthy`.
- If errors stop and endpoint returns `200`, treat as startup window noise.

## Rollback

### Cloud Run

- Roll back traffic to previous revision:

```bash
gcloud run services update-traffic openclawbot-svc-plus \
  --region=asia-northeast1 \
  --to-revisions=<previous-revision>=100
```

### Single host

- Restore previous config:

```bash
cp /data/openclaw.json.bak-<timestamp> /data/openclaw.json
systemctl restart openclawbot-svc-plus
```

## Final Acceptance Checklist

- Bucket `openclawbot-data` is mounted at `/data`.
- `OPENCLAW_STATE_DIR` points to `/data`.
- `OPENCLAW_CONFIG_PATH` points to `/data/openclaw.json`.
- `OPENCLAW_GATEWAY_TOKEN` and `Z_AI_API_KEY` come from secure secret sources.
- Single host ingress is Caddy with valid TLS certificate.
- `openclawbot-svc-plus` is reachable and stable through the public domain.
