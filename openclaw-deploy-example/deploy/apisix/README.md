# APISIX Gateway Mirror

`deploy/apisix/example/vps/` is the local mirror of `root@openclaw.svc.plus:/opt/svc-ai-gateway/` captured on 2026-03-10.

## Layout

- Base online mirror lives under `example/vps/`.
- macOS-local env overrides live under `macos/`.
- Shared config sync is handled by `scripts/sync-config.sh`.

## Shared vs local-private files

Shared by default:

- `conf/apisix.yaml`
- `conf/config.yaml`
- `docker-compose.yml`
- `docs/api.md`
- `docs/models.md`
- `docs/providers.md`
- `scripts/healthcheck.sh`
- `scripts/reload.sh`
- `scripts/validate.sh`

Local-only by default:

- `macos/.env.local`
- `macos/Caddyfile`

Optional sync targets:

- `Caddyfile` with `--with-edge`
- `.env` with `--with-env`

## macOS local APISIX

The local macOS variant no longer uses Docker or Caddy. It runs as a native local process and exposes only the proxy listener:

- APISIX HTTP proxy: `http://127.0.0.1:9080`
- Admin API: disabled
- Control API: disabled

Expected local runtime:

- OpenResty under `~/.local/openresty`
- APISIX source/runtime under `~/.local/src/apisix`

Quick start:

```bash
cd deploy/apisix
cp macos/.env.local.example macos/.env.local
./scripts/run-local-macos.sh validate
./scripts/run-local-macos.sh up
./scripts/run-local-macos.sh status
```

Smoke test:

```bash
curl -H "Authorization: Bearer <AI_GATEWAY_ACCESS_TOKEN>" \
  http://127.0.0.1:9080/v1/models
```

Useful actions:

```bash
./scripts/run-local-macos.sh down
./scripts/run-local-macos.sh restart
./scripts/run-local-macos.sh logs
./scripts/run-local-macos.sh smoke
```

If you want a TLS edge on macOS as well, use the separate local Caddy profile under `deploy/caddy/macos/`.

## Config sync

Compare local shared config against the online deployment:

```bash
cd deploy/apisix
./scripts/sync-config.sh diff
```

Pull the online shared config down again:

```bash
cd deploy/apisix
./scripts/sync-config.sh pull
```

Push shared config back to the online node:

```bash
cd deploy/apisix
./scripts/sync-config.sh push
```

Include online `.env` only when you explicitly want to sync secrets:

```bash
./scripts/sync-config.sh pull --with-env
./scripts/sync-config.sh push --with-env
```

Include the online edge `Caddyfile` only when you intentionally want to align the public host proxy layer too:

```bash
./scripts/sync-config.sh diff --with-edge
```
