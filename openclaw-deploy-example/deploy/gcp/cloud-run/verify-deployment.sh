#!/bin/bash
set -e

PROJECT_ID="${GCP_PROJECT_ID:-xzerolab-480008}"
REGION="${GCP_REGION:-asia-northeast1}"
SERVICE_NAME="openclawbot-svc-plus"

echo "🔍 Verifying Cloud Run deployment..."
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Service: $SERVICE_NAME"
echo ""

# Check service status
echo "📊 Service Status:"
gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(status.conditions[0].type,status.conditions[0].status,status.conditions[0].message,status.url)"

echo ""
echo "📋 Latest Revisions:"
gcloud run revisions list \
  --service="${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --limit=3 \
  --format="table(metadata.name,status.conditions[0].status,status.conditions[0].reason,metadata.creationTimestamp)"

echo ""
echo "🔐 Environment Variables:"
gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(spec.template.spec.containers[0].env)" | grep -E "(name:|value:|valueFrom:)" | head -20

echo ""
echo "📝 Recent Logs (last 20 lines):"
gcloud run services logs read "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --limit=20 2>/dev/null || echo "No logs available yet"

echo ""
echo "✅ Verification complete"
