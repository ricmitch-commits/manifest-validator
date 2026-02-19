#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

WORK_DIR="$1"
K8S_VERSION="${KUBERNETES_VERSION:-1.28.0}"


# Run kubeconform in strict mode to catch all schema violations including missing required fields
# -strict: Enforce strict validation (additional properties not allowed)
# -output json: JSON output for easy parsing
# -skip CustomResourceDefinition: Skip CRDs as they may not have schemas
# -verbose: Show detailed error messages
kubeconform \
    -kubernetes-version "$K8S_VERSION" \
    -ignore-missing-schemas \
    -strict \
    -output json \
    -verbose \
    -skip CustomResourceDefinition \
    "$WORK_DIR"
