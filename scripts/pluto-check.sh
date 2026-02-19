#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

WORK_DIR="$1"
TARGET_K8S_VERSION="${TARGET_KUBERNETES_VERSION:-v1.29.0}"

pluto detect-files \
    -d "$WORK_DIR" \
    --target-versions "k8s=$TARGET_K8S_VERSION" \
    -o json
