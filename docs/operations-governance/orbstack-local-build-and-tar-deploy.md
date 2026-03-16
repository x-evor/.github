# OrbStack Local Build and Tar Deploy

This workflow is the preferred path for single-node VPS releases when running on macOS.

## Why OrbStack

| Benefit | Why it matters |
| --- | --- |
| Stable local Docker daemon | Avoids remote host builds for every release |
| Local `linux/amd64` image build | Matches the VPS runtime architecture |
| Faster debugging | Rebuild and rerun locally before touching `us-xhttp` |
| Lower VPS risk | The VPS only needs `docker load` and `docker compose up` |

## Prerequisites

| Item | Requirement |
| --- | --- |
| Local runtime | OrbStack installed and running |
| Docker CLI | `docker info` must succeed locally |
| SSH access | Working SSH access to `root@us-xhttp.svc.plus` |
| Remote Docker | Docker Engine + Compose plugin installed on the VPS |

## Standard Flow

1. Build the image locally with OrbStack
2. Save it as a tar archive
3. Transfer the tar to the target release directory
4. `docker load` on the VPS
5. Render `docker-compose.yml` and `env/app.env`
6. Run `docker compose up -d`
7. Validate loopback and release-domain health checks

## Helper Scripts

| Script | Purpose |
| --- | --- |
| `scripts/single-node/build_local_image_tar.sh` | Build a local image and export it as a tar archive |
| `scripts/single-node/ship_image_tar.sh` | Transfer a tar archive to the VPS and run `docker load` |

## Example: accounts.svc.plus

### 1. Build the local image tar

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit

scripts/single-node/build_local_image_tar.sh \
  --context /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus \
  --image local/accounts \
  --tag "$(git -C /Users/shenlan/workspaces/cloud-neutral-toolkit/accounts.svc.plus rev-parse --short HEAD)" \
  --tar /tmp/accounts-latest.tar \
  --platform linux/amd64
```

### 2. Transfer and load on the VPS

```bash
scripts/single-node/ship_image_tar.sh \
  --host root@us-xhttp.svc.plus \
  --tar /tmp/accounts-latest.tar \
  --remote-dir /opt/cloud-neutral/accounts/accounts-us-xhttp-<git-short-commit>
```

### 3. Start the release

```bash
ssh root@us-xhttp.svc.plus '
docker compose -f /opt/cloud-neutral/accounts/accounts-us-xhttp-<git-short-commit>/docker-compose.yml up -d --remove-orphans
docker compose -f /opt/cloud-neutral/accounts/accounts-preview-us-xhttp-<git-short-commit>/docker-compose.yml up -d --remove-orphans
'
```

### 4. Verify

```bash
ssh root@us-xhttp.svc.plus '
curl -sf http://127.0.0.1:18080/healthz
curl -sf http://127.0.0.1:18081/healthz
curl -skf https://accounts-us-xhttp-<git-short-commit>.svc.plus/healthz
curl -skf https://accounts-preview-us-xhttp-<git-short-commit>.svc.plus/healthz
'
```

## Notes

| Topic | Guidance |
| --- | --- |
| Secrets | Keep real values in `.env`, Vault, or runtime env injection; do not commit them |
| Architecture | Build `linux/amd64` images even on Apple Silicon |
| SSH stability | Large image transfers are more reliable with `rsync` than Ansible `copy` |
| DNS cutover | Keep stable domains pending until the release domain is healthy |
