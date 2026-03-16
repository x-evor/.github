#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <metadata|ansible>" >&2
  exit 1
fi

mode="$1"

python -m pip install --upgrade pip

case "${mode}" in
  metadata)
    python -m pip install "PyYAML==6.0.3"
    ;;
  ansible)
    python -m pip install "ansible-core==2.18.3"
    ;;
  *)
    echo "unknown install mode: ${mode}" >&2
    exit 1
    ;;
esac
