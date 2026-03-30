# openclaw_gateway

Role for deploying or migrating the OpenClaw gateway service.

## What it manages

- Node.js runtime for the OpenClaw CLI/service
- OpenClaw runtime state under `~/.openclaw`
- Optional migration of `/opt/data/`
- Optional GCS mount for `/opt/data`
- User-level `openclaw-gateway.service`
- Caddy reverse proxy for `openclaw.svc.plus`
- Optional Cloudflare DNS record management
- Optional Docker-based deployment mode

## Modes

### Runtime mode

- `openclaw_runtime_mode: systemd`
- `openclaw_runtime_mode: docker`

### Data backend

- `openclaw_data_backend: local`
- `openclaw_data_backend: gcs`

## Important variables

- `openclaw_source_host`
  - Source host to read migration artifacts from.
  - Default: `openclaw.svc.plus`
- `openclaw_domain`
  - Public hostname for the gateway.
  - Default: `openclaw.svc.plus`
- `openclaw_service_port`
  - Local gateway port exposed to Caddy.
  - Default: `18789`
- `openclaw_workspace`
  - Data directory mounted or created on the target host.
  - Default: `/opt/data`
- `openclaw_data_backend`
  - `local` uses a normal filesystem directory.
  - `gcs` mounts a GCS bucket with gcsfuse.
- `openclaw_manage_migration`
  - Enables migration from the source host.
  - Default: `false`
- `openclaw_migrate_data_dir`
  - Copies `/opt/data/` from the source host when `local` backend is used.
  - Default: `false`
- `openclaw_manage_runtime_state`
  - Migrates `~/.env`, `~/.openclaw/openclaw.json`, and related state.
  - Default: `true`
- `openclaw_manage_caddy`
  - Installs and reloads Caddy site config.
  - Default: `true`
- `openclaw_manage_dns`
  - Creates/updates the Cloudflare DNS record.
  - Default: `false`
- `openclaw_runtime_mode`
  - `systemd` uses a user service.
  - `docker` uses a Compose file plus a systemd wrapper.
- `openclaw_docker_image`
  - Required when `openclaw_runtime_mode: docker`.
- `openclaw_cloudflare_api_token`
  - Required when `openclaw_manage_dns: true`.
- `openclaw_cloudflare_zone_name`
  - Used to resolve the zone id automatically.
- `openclaw_cloudflare_zone_id`
  - Can be set directly to skip lookup.

## Dependencies

- Caddy
- Node.js 22+
- npm
- gcsfuse when `openclaw_data_backend: gcs`
- Cloudflare API token when `openclaw_manage_dns: true`

## Usage

### Deploy to a fresh target host

```yaml
---
- name: Deploy OpenClaw gateway
  hosts: gateway
  become: true
  gather_facts: true
  roles:
    - role: openclaw_gateway
      vars:
        openclaw_source_host: openclaw.svc.plus
        openclaw_domain: openclaw.svc.plus
        openclaw_runtime_mode: systemd
        openclaw_data_backend: local
        openclaw_manage_migration: false
        openclaw_manage_caddy: true
        openclaw_manage_dns: true
        openclaw_cloudflare_zone_name: svc.plus
        openclaw_cloudflare_record_content: 46.250.251.132
```

### Migrate from the existing host

```yaml
---
- name: Migrate OpenClaw gateway
  hosts: gateway
  become: true
  gather_facts: true
  roles:
    - role: openclaw_gateway
      vars:
        openclaw_source_host: openclaw.svc.plus
        openclaw_manage_migration: true
        openclaw_migrate_data_dir: true
        openclaw_data_backend: local
        openclaw_manage_caddy: true
        openclaw_manage_dns: true
        openclaw_cloudflare_zone_name: svc.plus
        openclaw_cloudflare_record_content: 46.250.251.132
```

## Notes

- The role does not change the source host unless migration is explicitly enabled.
- Keep secrets out of the repo; pass Cloudflare tokens and any other sensitive values through vaulted vars or environment-backed vars.
