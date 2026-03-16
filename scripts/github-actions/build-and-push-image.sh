#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: $0 <service-checkout-path> <dockerfile-path> <build-context> <image-name> <deploy-prefix> <deploy-hostname> <domain>" >&2
  exit 1
fi

service_checkout_path="$1"
dockerfile_path="$2"
build_context="$3"
image_name="$4"
deploy_prefix="$5"
deploy_hostname="$6"
domain="$7"

: "${GHCR_REGISTRY:?GHCR_REGISTRY is required}"
: "${SERVICE_REPO_OWNER:?SERVICE_REPO_OWNER is required}"

short_sha="$(git -C "${service_checkout_path}" rev-parse --short HEAD)"
image_ref="${GHCR_REGISTRY}/${SERVICE_REPO_OWNER}/${image_name}:${short_sha}"
release_domain="${deploy_prefix}-${deploy_hostname}-${short_sha}.${domain}"

docker buildx build \
  --platform linux/amd64 \
  --file "${service_checkout_path}/${dockerfile_path}" \
  --tag "${image_ref}" \
  --push \
  "${service_checkout_path}/${build_context}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "git_short_commit=${short_sha}"
    echo "image_ref=${image_ref}"
    echo "release_domain=${release_domain}"
  } >> "${GITHUB_OUTPUT}"
else
  cat <<EOF
git_short_commit=${short_sha}
image_ref=${image_ref}
release_domain=${release_domain}
EOF
fi
