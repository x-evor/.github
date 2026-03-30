# OpenClaw VPS Inspection Report

## Access Status
- SSH access to `root@openclaw.svc.plus` succeeded.
- Host reported by the machine is `cn-hub.svc.plus`.
- Inspection was read-only; no changes were made on the host.

## Service Summary
- `systemd` is healthy: `running`, with no failed units.
- Key services are up:
  - `caddy.service`: active/running
  - `xray.service`: active/running
  - `docker.service` and `containerd.service`: active/running
  - `vault.service`, `privoxy.service`, `ssh.service`, `chrony.service`, `systemd-networkd.service`: active/running
- Requested units not present:
  - `xray-tcp.service`
  - `haproxy.service`
  - `agent-svc-plus.service`
- Recent service logs for `xray` and `caddy` show normal proxy traffic plus occasional reverse-proxy `broken pipe` / `context canceled` events. No service outage was evident.

## System Summary
- Kernel: Ubuntu 6.8.0-59-generic
- Uptime: 11 days
- Load average: 0.15, 0.43, 0.58
- System state: `running`

## Storage Summary
- Root filesystem: 59G total, 26G used, 31G free, 46% used.
- Inodes: 14% used, so inode pressure is not a concern.
- Journal usage is sizable: `journalctl --disk-usage` reports 2.7G.
- `/var/cache/apt/archives` is 421M.

## Memory / CPU Summary
- Memory: 3.6Gi total, 1.0Gi available.
- Swap: 1.9Gi total, 461Mi used.
- No immediate memory crisis, but the host is moderately warm.
- Largest memory consumers:
  - `openclaw-gateway` at ~36.9% RSS
  - `gcsfuse`
  - `fwupd`
  - `systemd-journald`
  - `syncthing`
  - `vault`
  - `xray`
- CPU usage is low overall; no runaway process was observed.

## Network Summary
- Active listeners include:
  - `caddy` on `:443` and localhost `:2019`
  - `xray` on localhost `:1080` and `:1081`
  - `vault` on localhost `:8200` and `:8201`
  - `privoxy` on localhost `:8118`
  - `openclaw-gateway` on localhost and port `18789`
  - `ssh` on `:22`
- Interfaces present: `eth0`, `wg0`, `br0`, `docker0`, and Docker bridge interfaces.
- Default route is via `10.0.4.1` on `eth0`.

## Docker Summary
- Docker is installed and running.
- One container is active:
  - `svc-ai-gateway` from `apache/apisix:3.15.0-debian`
- `docker system df` shows:
  - Images: 3.425GB total
  - Reclaimable images: 3.018GB
  - Containers: negligible disk use
  - Volumes: none

## Safe Cleanup Candidates
- `journalctl --vacuum-time=7d` would likely reclaim a meaningful amount of space, based on 2.7G of journal usage.
- `apt-get clean` would likely reclaim up to the 421M in `/var/cache/apt/archives`.
- `docker image prune` could reclaim unused image space, with about 3.0G shown as reclaimable.

## Risks / Anomalies
- No active host outage or failed systemd unit was found.
- The largest operational signals are storage growth in journals and Docker images, not disk exhaustion.
- Caddy logs show frequent internet scan traffic and occasional upstream proxy interruptions, which should be monitored but do not currently indicate a service failure.
