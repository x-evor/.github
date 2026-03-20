#!/bin/bash
set -euo pipefail

# Cloud Run Deployment Script for OpenClawBot
# Unified script: includes Secret Manager setup + Cloud Run deployment.

PROJECT_ID="${GCP_PROJECT_ID:-xzerolab-480008}"
REGION="${GCP_REGION:-asia-northeast1}"
SERVICE_NAME="openclawbot-svc-plus"
GCS_BUCKET="${GCS_BUCKET_NAME:-openclawbot-data}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT_EMAIL:-openclawbot-sa@${PROJECT_ID}.iam.gserviceaccount.com}"
SECRET_NAME="${OPENCLAW_GATEWAY_SECRET_NAME:-internal-service-token}"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

echo "🚀 Deploying OpenClawBot to Cloud Run..."
echo "   Project: ${PROJECT_ID}"
echo "   Region: ${REGION}"
echo "   Service: ${SERVICE_NAME}"
echo "   GCS Bucket: ${GCS_BUCKET}"
echo "   Secret: ${SECRET_NAME}"
echo ""

# Step 1: Create secret if missing (requires OPENCLAW_GATEWAY_TOKEN for first-time setup)
echo "🔐 Checking Secret Manager..."
if gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "   ✅ Secret '${SECRET_NAME}' already exists"
else
  if [[ -z "${GATEWAY_TOKEN}" ]]; then
    echo "   ❌ Secret '${SECRET_NAME}' does not exist."
    echo "   Set OPENCLAW_GATEWAY_TOKEN to create it, then rerun."
    exit 1
  fi
  echo "   Creating secret '${SECRET_NAME}'..."
  printf '%s' "${GATEWAY_TOKEN}" | \
    gcloud secrets create "${SECRET_NAME}" \
      --data-file=- \
      --project="${PROJECT_ID}" \
      --replication-policy="automatic"
  echo "   ✅ Secret created"
fi

# Step 2: Create GCS bucket if it doesn't exist
echo "📦 Checking GCS bucket..."
if ! gsutil ls -b "gs://${GCS_BUCKET}" &>/dev/null; then
  echo "   Creating GCS bucket: ${GCS_BUCKET}"
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${GCS_BUCKET}"
  echo "   ✅ Bucket created"
else
  echo "   ✅ Bucket already exists"
fi

# Step 3: Create service account if it doesn't exist
echo "🔐 Checking service account..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "   Creating service account..."
  gcloud iam service-accounts create "openclawbot-sa" \
    --display-name="OpenClawBot Service Account" \
    --project="${PROJECT_ID}"
  echo "   ✅ Service account created"
  echo "   ⏳ Waiting for service account to propagate..."
  sleep 10
else
  echo "   ✅ Service account already exists"
fi

# Step 4: Grant required IAM permissions
echo "🔑 Granting permissions..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/storage.objectAdmin" \
  --condition=None \
  --quiet

gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="${PROJECT_ID}" \
  --quiet

echo "   ✅ Permissions granted"

# Step 5: Build and deploy
echo "🏗️  Building and deploying to Cloud Run..."
gcloud run deploy "${SERVICE_NAME}" \
  --source . \
  --platform managed \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --service-account "${SERVICE_ACCOUNT}" \
  --execution-environment gen2 \
  --cpu 2 \
  --memory 4Gi \
  --min-instances 1 \
  --max-instances 10 \
  --no-cpu-throttling \
  --allow-unauthenticated \
  --port 8080 \
  --update-secrets OPENCLAW_GATEWAY_TOKEN="${SECRET_NAME}:latest",INTERNAL_SERVICE_TOKEN="${SECRET_NAME}:latest",ZAI_API_KEY=zai-api-key:latest,Z_AI_API_KEY=zai-api-key:latest \
  --set-env-vars NODE_ENV=production,OPENCLAW_STATE_DIR=/data,OPENCLAW_CONFIG_PATH=/data/openclaw.json,OPENCLAW_GATEWAY_MODE=local,OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=*,OPENCLAW_GATEWAY_CONTROL_UI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK=true \
  --add-volume name=gcs-data,type=cloud-storage,bucket="${GCS_BUCKET}" \
  --add-volume-mount volume=gcs-data,mount-path=/data \
  --quiet

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Service URL:"
gcloud run services describe "${SERVICE_NAME}" \
  --platform managed \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format 'value(status.url)'

echo ""
echo "🔐 Secret Manager:"
echo "   Secret: ${SECRET_NAME}"
echo "   Version: latest"
