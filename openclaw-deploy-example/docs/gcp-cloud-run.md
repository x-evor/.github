# Deploying OpenClaw Gateway on Google Cloud Run (Gateway Only Mode)

This guide covers how to deploy OpenClaw in a "Gateway Only" configuration on Cloud Run, optimized for low overhead and using Zhipu AI (ZAI/GLM) as the primary provider.

For the full production runbook including single host Caddy plus Docker plus JuiceFS operations, see [OpenClaw Deployment Runbook](/runbook-cloud-run).
For the multi-gateway layout with Kong as the unified remote entrypoint and independent node configs, see [OpenClaw Multi-Gateway Architecture](multi-gateway-architecture.md).
For Windows / macOS / Linux shared mounts, use [JuiceFS + PostgreSQL + GCS](juicefs-gcs-mount.md) instead of treating Cloud Run's GCS volume as the shared filesystem.

## Architecture

- **Cloud Run**: Runs the OpenClaw Gateway container.
- **Cloud Storage (GCS)**: Mounted as a volume at `/data` for node-local Cloud Run state and compatibility storage.
- **Secret Manager**: Securely stores `OPENCLAW_GATEWAY_TOKEN` and `ZAI_API_KEY`.
- **Cloud Build**: Automates building and deploying the container.
- **Kong**: Stays in front of remote gateways as the centralized auth, routing, and AI API governance layer.

Cloud Run is recommended only for non-interactive online work, overflow, and failover. Strong interactive browser tasks should stay on the local macOS gateway. The Cloud Run GCS volume remains the default for this path, but it is not the recommended shared mount pattern for desktop or server clients.

## Prerequisites

1.  A Google Cloud Project with billing enabled.
2.  GCS Bucket named `openclawbot-data`.
3.  Secret Manager secrets:
    - `internal-service-token`: Used for `OPENCLAW_GATEWAY_TOKEN`.
    - `zai-api-key`: Your Zhipu AI API key.
4.  Service Account `openclawbot-sa` with permissions:
    - Cloud Run Developer
    - Secret Manager Secret Accessor
    - Storage Object Admin (for the bucket)

## Minimal Configuration

### Environment Variables (Server-side)

The following variables are configured in `cloudbuild.yaml`:

- `NODE_ENV=production`
- `OPENCLAW_STATE_DIR=/data`
- `OPENCLAW_CONFIG_PATH=/data/openclaw.json`
- `OPENCLAW_GATEWAY_MODE=local`: Forces the gateway to run as the master node.
- `OPENCLAW_GATEWAY_TOKEN`: Sourced from Secret Manager (`internal-service-token`).
- `ZAI_API_KEY`: Sourced from Secret Manager (`zai-api-key`).

### Deployment Step (`cloudbuild.yaml`)

```yaml
- name: "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
  entrypoint: "gcloud"
  args:
    - "run"
    - "deploy"
    - "openclawbot-svc-plus"
    - "--region=asia-northeast1"
    - "--image=asia-northeast1-docker.pkg.dev/$PROJECT_ID/..."
    - "--set-env-vars=NODE_ENV=production,OPENCLAW_STATE_DIR=/data,OPENCLAW_CONFIG_PATH=/data/openclaw.json,OPENCLAW_GATEWAY_MODE=local"
    - "--update-secrets=OPENCLAW_GATEWAY_TOKEN=internal-service-token:latest,INTERNAL_SERVICE_TOKEN=internal-service-token:latest,ZAI_API_KEY=zai-api-key:latest"
    - "--add-volume=name=gcs-data,type=cloud-storage,bucket=openclawbot-data"
    - "--add-volume-mount=volume=gcs-data,mount-path=/data"
```

## How to Deploy

1.  Ensure your secrets are created in Secret Manager.
2.  Run the build using gcloud:
    ```bash
    gcloud builds submit --config cloudbuild.yaml --substitutions=COMMIT_SHA=$(git rev-parse HEAD)
    ```

## Post-Deployment Configuration (openclaw.json)

Once deployed, the `openclaw.json` in your GCS bucket should be updated using our optimized template as a base. You can find this template at:
`example/config/openclaw.json`

The key configurations for this environment are:

- **`agents.defaults.workspace`**: Set to `/data/workspace`.
- **`auth.profiles`**: Configured for `zai` using environment-injected API keys.
- **`gateway.controlUi`**: `dangerouslyDisableDeviceAuth` set to `true` for easier access in Cloud Run.

The `ZAI_API_KEY` and `OPENCLAW_GATEWAY_TOKEN` environment variables injected by Cloud Run (via Secret Manager) will be automatically picked up by the system.

## Troubleshooting

- **Container failed to start**: Check Cloud Logging. Common causes include missing secrets or incorrect GCS bucket permissions.
- **Gateway token mismatch**: Ensure the token you use in the Control UI matches the value in the `internal-service-token` secret.
- **Plugin not found**: Ensure your `Dockerfile` copies the `extensions` and `skills` directories to the runtime stage.
