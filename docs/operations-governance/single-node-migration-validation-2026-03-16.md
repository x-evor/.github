# Single-Node Migration Validation (2026-03-16)

Target host: `root@us-xhttp.svc.plus (5.78.45.49)`

Database runtime:

- Physical DB host: `ubuntu@jp-xhttp.svc.plus`
- Service-side TLS endpoint: `postgresql-aws.svc.plus:5443`

## Release Validation

| Service | Repo | Release Domain | Check Command | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| `accounts` prod | `accounts.svc.plus` | `https://accounts-us-xhttp-c1df654c.svc.plus/healthz` | `curl -skf https://accounts-us-xhttp-c1df654c.svc.plus/healthz` | `200` | Returns `{"status":"ok"}` |
| `accounts` preview | `accounts.svc.plus` | `https://accounts-preview-us-xhttp-c1df654c.svc.plus/healthz` | `curl -skf https://accounts-preview-us-xhttp-c1df654c.svc.plus/healthz` | `200` | Returns `{"status":"ok"}` |
| `rag-server` | `rag-server.svc.plus` | `https://rag-server-us-xhttp-8ca3e271.svc.plus/healthz` | `curl -skf https://rag-server-us-xhttp-8ca3e271.svc.plus/healthz` | `200` | Returns `{"auth":"enabled","status":"ok"}` |
| `x-cloud-flow` | `x-cloud-flow.svc.plus` | `https://x-cloud-flow-us-xhttp-458f542.svc.plus/healthz` | `curl -sk -o /dev/null -w "%{http_code}\n" https://x-cloud-flow-us-xhttp-458f542.svc.plus/healthz` | `200` | Health endpoint returns status code only |
| `x-ops-agent` | `x-ops-agent.svc.plus` | `https://x-ops-agent-us-xhttp-7499c4b.svc.plus/healthz` | `curl -skf https://x-ops-agent-us-xhttp-7499c4b.svc.plus/healthz` | `200` | Returns `{"status":"ok","gateway_configured":false,"codex_configured":true}` |
| `x-scope-hub` | `x-scope-hub.svc.plus` | `https://x-scope-hub-us-xhttp-9a1a482.svc.plus/manifest` | `curl -skf https://x-scope-hub-us-xhttp-9a1a482.svc.plus/manifest` | `200` | Returns MCP manifest JSON |

## Container Ports

| Service | Container Name | Loopback Port | Verification |
| --- | --- | --- | --- |
| `accounts` prod | `accounts-us-xhttp-c1df654c` | `127.0.0.1:18080` | `curl -sf http://127.0.0.1:18080/healthz` |
| `accounts` preview | `accounts-preview-us-xhttp-c1df654c` | `127.0.0.1:18081` | `curl -sf http://127.0.0.1:18081/healthz` |
| `rag-server` | `rag-server-us-xhttp-8ca3e271` | `127.0.0.1:18082` | `curl -sf http://127.0.0.1:18082/healthz` |
| `x-cloud-flow` | `x-cloud-flow-us-xhttp-458f542` | `127.0.0.1:18083` | `curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:18083/healthz` |
| `x-ops-agent` | `x-ops-agent-us-xhttp-7499c4b` | `127.0.0.1:18084` | `curl -sf http://127.0.0.1:18084/healthz` |
| `x-scope-hub` | `x-scope-hub-us-xhttp-9a1a482` | `127.0.0.1:18085` | `curl -sf http://127.0.0.1:18085/manifest` |

## Current Status

| Item | Status | Note |
| --- | --- | --- |
| Release-domain DNS | Done | All listed release domains resolve to `5.78.45.49` |
| Release-domain HTTPS | Done | Release-domain certificates issued and validated |
| Stable-domain CNAME cutover | Pending | Must be switched manually after release confirmation |
| DB connectivity | Done | `accounts` and `rag-server` validated through TLS tunnel |
| Old `x-scope-hub.service` | Disabled | Replaced by Docker Compose release container |

## Next Step

Manually switch each stable domain to the matching release-domain CNAME:

| Stable Domain | Target Release Domain |
| --- | --- |
| `accounts.svc.plus` | `accounts-us-xhttp-c1df654c.svc.plus` |
| `accounts-preview.svc.plus` | `accounts-preview-us-xhttp-c1df654c.svc.plus` |
| `rag-server.svc.plus` | `rag-server-us-xhttp-8ca3e271.svc.plus` |
| `x-cloud-flow.svc.plus` | `x-cloud-flow-us-xhttp-458f542.svc.plus` |
| `x-ops-agent.svc.plus` | `x-ops-agent-us-xhttp-7499c4b.svc.plus` |
| `x-scope-hub.svc.plus` | `x-scope-hub-us-xhttp-9a1a482.svc.plus` |
