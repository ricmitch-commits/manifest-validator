#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

OUTPUT_DIR="$1"
POLICIES_DIR="$2"

log_info "Applying Kyverno mutation policies from $POLICIES_DIR"

# Check if policies directory exists and has policies
if [ ! -d "$POLICIES_DIR" ] || [ -z "$(ls -A "$POLICIES_DIR"/*.yaml 2>/dev/null)" ]; then
    log_warn "No Kyverno policies found in $POLICIES_DIR"
    return 0
fi

# Apply each mutation policy to each manifest
for policy in "$POLICIES_DIR"/*.yaml; do
    policy_name=$(basename "$policy" .yaml)
    log_info "Processing policy: $policy_name"

    for manifest in "$OUTPUT_DIR"/*.yaml "$OUTPUT_DIR"/*.yml; do
        if [ ! -f "$manifest" ]; then
            continue
        fi

        manifest_name=$(basename "$manifest")

        # Run kyverno apply with mutation output
        # kyverno apply returns mutated resources on stdout
        mutated_output=$(kyverno apply "$policy" \
            --resource "$manifest" \
            -o yaml 2>/dev/null || true)

        # Check if mutation produced output
        if [ -n "$mutated_output" ] && [ "$mutated_output" != "---" ]; then
            # Extract the actual resource (skip kyverno metadata)
            resource_output=$(echo "$mutated_output" | yq eval 'select(.kind != "PolicyReport")' -)

            if [ -n "$resource_output" ] && [ "$resource_output" != "null" ]; then
                echo "$resource_output" > "$manifest"
                log_info "  Applied $policy_name to $manifest_name"
            fi
        fi
    done
done

log_info "All Kyverno mutations applied"
