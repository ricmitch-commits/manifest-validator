#!/bin/bash
set -uo pipefail

# Source utilities
source /home/argocd/scripts/utils.sh

# Configuration
# CMP receives files in current directory, not in ARGOCD_APP_SOURCE_PATH
WORK_DIR="."
OUTPUT_DIR="/tmp/validated-manifests"
POLICIES_DIR="/home/argocd/policies"

# Initialize arrays
HIGH_IMPACT_ERRORS=()
LOW_IMPACT_ERRORS=()

# Initialize
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
log_info "Starting manifest validation for: $WORK_DIR"

# Step 1: Collect all YAML files (excluding kustomization and non-manifest files)
YAML_FILES=$(find "$WORK_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -name "kustomization.yaml" \
    ! -name "kustomization.yml" \
    ! -name "Kustomization" \
    ! -name ".*.yaml" \
    ! -name ".*.yml" \
    | sort)
if [ -z "$YAML_FILES" ]; then
    log_warn "No YAML files found in $WORK_DIR"
    exit 0
fi

log_info "Found $(echo "$YAML_FILES" | wc -l | tr -d ' ') YAML files to validate"

# Step 2: Run validation tools and collect results

# Run Kubeconform (schema validation)
log_info "Running Kubeconform schema validation..."
K8S_VERSION="${KUBERNETES_VERSION:-1.28.0}"
log_info "Kubeconform: validating against Kubernetes $K8S_VERSION schema"
/home/argocd/scripts/kubeconform-check.sh "$WORK_DIR" > /tmp/kubeconform-output.json 2>&1 || true
classify_kubeconform_errors /tmp/kubeconform-output.json

# Run Pluto (deprecated API detection)
log_info "Running Pluto deprecated API detection..."
TARGET_K8S_VERSION="${TARGET_KUBERNETES_VERSION:-v1.29.0}"
log_info "Pluto: checking for deprecated APIs against Kubernetes $TARGET_K8S_VERSION"
/home/argocd/scripts/pluto-check.sh "$WORK_DIR" > /tmp/pluto-output.json 2>&1 || true
classify_pluto_errors /tmp/pluto-output.json

# Run KubeLinter (best practices)
log_info "Running KubeLinter best practices check..."
/home/argocd/scripts/kubelinter-check.sh "$WORK_DIR" > /tmp/kubelinter-output.json 2>&1 || true
classify_kubelinter_errors /tmp/kubelinter-output.json

# Step 3: Log findings
log_info "Validation complete: ${#HIGH_IMPACT_ERRORS[@]} high-impact, ${#LOW_IMPACT_ERRORS[@]} low-impact issues"

# Step 4: Handle HIGH IMPACT errors (rollback)
if [ ${#HIGH_IMPACT_ERRORS[@]} -gt 0 ]; then
    log_error "HIGH IMPACT errors detected - initiating git rollback"

    # Log all high impact errors
    for err in "${HIGH_IMPACT_ERRORS[@]}"; do
        log_error "  - $err"
    done

    # Generate error report
    generate_error_report "HIGH_IMPACT" "${HIGH_IMPACT_ERRORS[@]}"

    # Perform git rollback if credentials are available
    if [ -f "/home/argocd/.ssh/id_rsa" ] && [ -n "${ARGOCD_APP_SOURCE_REPO_URL:-}" ]; then
        log_info "Attempting git rollback..."
        /home/argocd/scripts/git-rollback.sh "${HIGH_IMPACT_ERRORS[@]}" || log_warn "Git rollback failed"
    else
        log_warn "Git credentials not available or repo URL not set, skipping rollback"
    fi

    # Exit with error - do not generate manifests
    log_error "Manifest validation failed due to high-impact errors"
    exit 1
fi

# Step 5: Handle LOW IMPACT errors (auto-fix)
if [ ${#LOW_IMPACT_ERRORS[@]} -gt 0 ]; then
    log_info "LOW IMPACT errors detected - applying auto-fixes"

    # Log low impact errors
    for err in "${LOW_IMPACT_ERRORS[@]}"; do
        log_warn "  - $err"
    done

    # Copy manifests to output directory
    for file in $YAML_FILES; do
        cp "$file" "$OUTPUT_DIR/"
    done

    # Apply Kyverno mutation policies
    /home/argocd/scripts/apply-fixes.sh "$OUTPUT_DIR" "$POLICIES_DIR"

    # Output fixed manifests
    log_info "Outputting fixed manifests..."
    for file in "$OUTPUT_DIR"/*.yaml "$OUTPUT_DIR"/*.yml; do
        if [ -f "$file" ]; then
            cat "$file"
            echo ""
            echo "---"
        fi
    done
else
    # No errors - output original manifests
    log_info "Validation passed - outputting manifests"
    for file in $YAML_FILES; do
        cat "$file"
        echo ""
        echo "---"
    done
fi

log_info "Manifest validation complete"
