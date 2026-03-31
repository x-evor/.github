#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 14 ]]; then
  echo "usage: $0 <artifact-mode> <service-checkout-path> <dockerfile-path> <build-context> <image-name> <prebuilt-image-ref> <release-version-strategy> <release-version-value> <release-dns-enabled> <release-dns-prefix> <release-vhost-name> <domain> <build-prepare-script> <build-args-script>" >&2
  exit 1
fi

artifact_mode="$1"
service_checkout_path="$2"
dockerfile_path="$3"
build_context="$4"
image_name="$5"
prebuilt_image_ref="$6"
release_version_strategy="$7"
release_version_value="$8"
release_dns_enabled="$9"
release_dns_prefix="${10}"
release_vhost_name="${11}"
domain="${12}"
build_prepare_script="${13}"
build_args_script="${14}"

sanitize_dns_label() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

git_short_commit=""
if git -C "${service_checkout_path}" rev-parse --git-dir >/dev/null 2>&1; then
  git_short_commit="$(git -C "${service_checkout_path}" rev-parse --short HEAD)"
fi

case "${release_version_strategy}" in
  git-short-commit)
    if [[ -z "${git_short_commit}" ]]; then
      echo "release_version.strategy=git-short-commit requires a git checkout at ${service_checkout_path}" >&2
      exit 1
    fi
    release_version="${git_short_commit}"
    ;;
  fixed)
    if [[ -z "${release_version_value}" ]]; then
      echo "release_version.value is required when strategy=fixed" >&2
      exit 1
    fi
    release_version="${release_version_value}"
    ;;
  *)
    echo "unsupported release version strategy: ${release_version_strategy}" >&2
    exit 1
    ;;
esac

release_version_dns_label="$(sanitize_dns_label "${release_version}")"
if [[ -z "${release_version_dns_label}" ]]; then
  echo "failed to derive a DNS-safe release version from '${release_version}'" >&2
  exit 1
fi

image_ref=""
case "${artifact_mode}" in
  build)
    : "${GHCR_REGISTRY:?GHCR_REGISTRY is required}"
    : "${SERVICE_REPO_OWNER:?SERVICE_REPO_OWNER is required}"
    : "${git_short_commit:?git short commit is required for build mode}"

    if [[ -n "${build_prepare_script}" ]]; then
      bash "${service_checkout_path}/${build_prepare_script}"
    fi

    image_ref="${GHCR_REGISTRY}/${SERVICE_REPO_OWNER}/${image_name}:${git_short_commit}"
    build_args=()
    if [[ -n "${build_args_script}" ]]; then
      while IFS= read -r build_arg; do
        [[ -n "${build_arg}" ]] || continue
        build_args+=(--build-arg "${build_arg}")
      done < <(bash "${service_checkout_path}/${build_args_script}" --stdout)
    fi

    docker buildx build \
      --platform linux/amd64 \
      --file "${service_checkout_path}/${dockerfile_path}" \
      --tag "${image_ref}" \
      --push \
      "${build_args[@]}" \
      "${service_checkout_path}/${build_context}"
    ;;
  prebuilt)
    image_ref="${prebuilt_image_ref}"
    if [[ -z "${image_ref}" ]]; then
      echo "prebuilt artifact mode requires a non-empty image ref" >&2
      exit 1
    fi
    ;;
  none)
    ;;
  *)
    echo "unsupported artifact mode: ${artifact_mode}" >&2
    exit 1
    ;;
esac

release_domain=""
if [[ "${release_dns_enabled}" == "true" ]]; then
  if [[ -z "${release_dns_prefix}" || -z "${release_vhost_name}" || -z "${domain}" ]]; then
    echo "release DNS is enabled but prefix/vhost/domain is missing" >&2
    exit 1
  fi
  release_domain="${release_dns_prefix}-${release_version_dns_label}-${release_vhost_name}.${domain}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "git_short_commit=${git_short_commit:-${release_version_dns_label}}"
    echo "release_version=${release_version}"
    echo "release_version_dns_label=${release_version_dns_label}"
    echo "image_ref=${image_ref}"
    echo "release_domain=${release_domain}"
    echo "release_dns_name=${release_domain}"
  } >> "${GITHUB_OUTPUT}"
else
  cat <<EOF
git_short_commit=${git_short_commit:-${release_version_dns_label}}
release_version=${release_version}
release_version_dns_label=${release_version_dns_label}
image_ref=${image_ref}
release_domain=${release_domain}
release_dns_name=${release_domain}
EOF
fi
