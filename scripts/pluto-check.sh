#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

WORK_DIR="$1"

pluto detect-files \
    -d "$WORK_DIR" \
    --target-versions "k8s=$TARGET_K8S_VERSION" \
    -o json
