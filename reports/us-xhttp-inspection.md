# us-xhttp.svc.plus VPS Inspection

## Access Status
- SSH access from `root@us-xhttp.svc.plus` succeeded.
- Hostname: `us-xhttp`
- Inspection timestamp on host: `2026-03-21T11:40:31+00:00`

## Service Summary
- `systemd` is `degraded`.
- Core services are running: `xray.service`, `xray-tcp.service`, `caddy.service`, `haproxy.service`, and `agent-svc-plus.service`.
- Failed units present: `dnsmasq.service` and `nginx.service`.
- `nginx.service` is blocked by port 80 already being used by `caddy.service`, so it looks like a stale or conflicting unit rather than the active web tier.
- `agent-svc-plus.service` is running but repeatedly logs controller `404 Not Found` errors while reporting status and syncing Xray config.

## System Summary
- Kernel: `6.8.0-90-generic` on Ubuntu.
- Uptime: about 7 days.
- Load average: `1.32, 0.59, 0.24`.
- Overall host health is acceptable, but `systemd` degraded status should be cleaned up.

## Storage Summary
- Root filesystem: `38G` total, `16G` used, `20G` free, `45%` utilized.
- Inodes: `15%` used.
- No immediate disk-pressure issue on `/`.

## Memory and CPU Summary
- Memory: `1.9Gi` total, `924Mi` available, no swap configured.
- Current pressure is moderate but not critical.
- Top memory consumers are `victoria-metrics` (`11.2%`), `grafana` (`9.8%`), `victoria-logs` (`5.9%`), `caddy`, `containerd`, and `vmalert`.
- Top CPU consumers are light; no runaway process was visible during the snapshot.

## Network Summary
- External address on `eth0`: `5.78.45.49/32`; IPv6 also present.
- Default route is via `172.31.1.1`.
- Key listeners: `22`, `80`, `443`, `1443`, `9101`, `9115`, and local Docker proxy ports.
- `caddy` owns `80/443`; `xray` owns `1443`; `haproxy` listens on `9101`.

## Docker Summary
- Docker is installed and active.
- Running containers: 7.
- `docker system df` shows `2.931GB` reclaimable images and `1.648GB` reclaimable build cache.
- No local volumes are present.

## Safe Cleanup Candidates
- Journals: `395MB` total.
- APT cache: `/var/cache/apt` at `612MB`.
- APT package lists: `/var/lib/apt/lists` at `228MB`.
- Docker image and build cache cleanup could reclaim about `4.6GB` combined, but only unused images and build cache should be considered.

## Risks / Anomalies
- `dnsmasq.service` and `nginx.service` are failed, which is what causes the `degraded` systemd state.
- `agent-svc-plus.service` is healthy enough to run, but its controller integration is failing with repeated `404` responses.
- `xray-tcp.service` logs recurring OCSP warnings about no OCSP server being specified in the certificate.
- `caddy` logs frequent reverse-proxy aborts to `unix//dev/shm/xray.sock` during active traffic; these did not appear to stop the service, but they merit follow-up if user traffic is affected.
