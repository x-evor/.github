#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <stage> [args...]" >&2
  exit 1
fi

stage="$1"
shift

case "${stage}" in
  stage1)
    if [[ $# -ne 8 ]]; then
      echo "usage: $0 stage1 <service> <track> <repo> <artifact-mode> <release-version> <image> <release-domain> <stable-domain>" >&2
      exit 1
    fi
    {
      echo "## Stage 1"
      echo "- service: \`$1\`"
      echo "- track: \`$2\`"
      echo "- repo: \`$3\`"
      echo "- artifact mode: \`$4\`"
      echo "- release version: \`$5\`"
      echo "- image: \`$6\`"
      echo "- release domain: \`$7\`"
      echo "- stable domain: \`$8\`"
    } >> "${GITHUB_STEP_SUMMARY}"
    ;;
  stage2)
    if [[ $# -ne 4 ]]; then
      echo "usage: $0 stage2 <track> <release-domain> <deploy-server-alias> <result>" >&2
      exit 1
    fi
    {
      echo "## Stage 2"
      echo "- track: \`$1\`"
      echo "- updated release DNS: \`$2\`"
      echo "- cname target: \`$3\`"
      echo "- result: \`$4\`"
    } >> "${GITHUB_STEP_SUMMARY}"
    ;;
  stage3)
    if [[ $# -ne 3 ]]; then
      echo "usage: $0 stage3 <service> <track> <playbook>" >&2
      exit 1
    fi
    {
      echo "## Stage 3"
      echo "- service: \`$1\`"
      echo "- track: \`$2\`"
      echo "- playbook: \`$3\`"
      echo "- mode: \`ansible-playbook -D -C\`"
    } >> "${GITHUB_STEP_SUMMARY}"
    ;;
  stage4)
    if [[ $# -ne 5 ]]; then
      echo "usage: $0 stage4 <service> <track> <playbook> <release-domain> <stable-domain>" >&2
      exit 1
    fi
    {
      echo "## Stage 4"
      echo "- service: \`$1\`"
      echo "- track: \`$2\`"
      echo "- playbook: \`$3\`"
      echo "- mode: \`ansible-playbook -D\`"
      echo "- release domain: \`$4\`"
      echo "- stable domain: \`$5\`"
    } >> "${GITHUB_STEP_SUMMARY}"
    ;;
  *)
    echo "unknown stage: ${stage}" >&2
    exit 1
    ;;
esac
