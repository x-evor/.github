# macOS Local Caddy Edge

This profile fronts the local macOS processes with public hostnames. The default
macOS mode uses Caddy's local `internal` CA so the local hostnames work even
without Cloudflare DNS write access. A separate `dns` mode is still available
for public ACME/DNS-challenge certificates when you have a Zone DNS-edit token.

- `ai.svc.plus` -> local APISIX first, fallback to public `api.svc.plus`
- `vault.svc.plus` -> local Vault first, fallback to public `vault.svc.plus`
- `openclaw.svc.plus` -> local OpenClaw first, fallback to public `openclaw.svc.plus`

As of 2026-03-10, `ai.svc.plus` does not have a public A record, so the online fallback for the AI gateway is intentionally `api.svc.plus`.

## Requirements

- local services already running:
  - APISIX `127.0.0.1:9080`
  - Vault `127.0.0.1:8200`
  - OpenClaw `127.0.0.1:18789`

## Quick start

```bash
cp deploy/caddy/macos/.env.local.example deploy/caddy/macos/.env.local
./scripts/run-local-caddy.sh build
./scripts/run-local-caddy.sh validate
./scripts/run-local-caddy.sh hosts-print
./scripts/run-local-caddy.sh up
./scripts/run-local-caddy.sh verify
```

If the local Vault, OpenClaw, and APISIX processes are not up yet, start the full stack first:

```bash
./scripts/run-ai-local-stack.sh up
./scripts/run-ai-local-stack.sh up-with-edge
./scripts/run-ai-local-stack.sh edge-verify
```

`build` first tries Caddy's official custom download endpoint for a `cloudflare`
DNS-enabled binary and falls back to local `xcaddy` only if the download fails.
If `CADDY_ACME_EMAIL` is left as `you@example.com`, the script automatically
falls back to the repository's configured `git user.email`.

`CADDY_TLS_MODE=internal` is the default local mode. If you want public
Let's Encrypt certificates instead, set `CADDY_TLS_MODE=dns` and provide a
Cloudflare token with permission to edit `_acme-challenge` TXT records for
`svc.plus`.

In `internal` mode, `./scripts/run-local-caddy.sh verify` uses Caddy's local
root CA file directly. If you also want browsers and the macOS system trust
store to accept the certificates without warnings, run `caddy trust` manually
and approve the password prompt.

## Hosts override

If you want browser traffic to prefer the local edge, add this to `/etc/hosts`:

```text
127.0.0.1 ai.svc.plus vault.svc.plus openclaw.svc.plus
```

Without hosts overrides, you can still verify locally with `curl --resolve ...`.

## Ports

The defaults are `8080` and `8443` so the edge can run as a normal macOS user.

If you want transparent browser access on standard ports, set:

```bash
LOCAL_EDGE_HTTP_PORT=80
LOCAL_EDGE_HTTPS_PORT=443
```

Then run the process with root privileges outside this repository workflow.
