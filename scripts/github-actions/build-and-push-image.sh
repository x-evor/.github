#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: $0 <service-checkout-path> <dockerfile-path> <build-context> <image-name> <deploy-prefix> <deploy-hostname> <domain> <track> <service-ref>" >&2
  exit 1
fi

service_checkout_path="$1"
dockerfile_path="$2"
build_context="$3"
image_name="$4"
deploy_prefix="$5"
deploy_hostname="$6"
domain="$7"
track="$8"
service_ref="$9"

: "${GHCR_REGISTRY:?GHCR_REGISTRY is required}"
: "${SERVICE_REPO_OWNER:?SERVICE_REPO_OWNER is required}"

short_sha="$(git -C "${service_checkout_path}" rev-parse --short HEAD)"
image_ref="${GHCR_REGISTRY}/${SERVICE_REPO_OWNER}/${image_name}:${short_sha}"
release_label=""
case "${service_ref}" in
  refs/heads/release/*)
    release_label="${service_ref#refs/heads/release/}"
    ;;
  release/*)
    release_label="${service_ref#release/}"
    ;;
esac
release_label="$(printf '%s' "${release_label}" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-')"

release_domain="${deploy_prefix}-${deploy_hostname}-${short_sha}.${domain}"
if [[ "${track}" == "prod" && -n "${release_label}" ]]; then
  release_domain="${deploy_prefix}-${deploy_hostname}-${release_label}-${short_sha}.${domain}"
fi

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
