#!/bin/bash

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# HIGH_IMPACT and LOW_IMPACT arrays for error classification
declare -a HIGH_IMPACT_ERRORS
declare -a LOW_IMPACT_ERRORS

# Error classification functions
classify_kubeconform_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    # Parse JSON output and classify - all schema errors are HIGH IMPACT
    # This includes: missing required fields, invalid values, type mismatches, etc.
    while IFS= read -r line; do
        local status=$(echo "$line" | jq -r '.status // empty' 2>/dev/null)

        # Catch all validation failures - statusInvalid, statusError, and any non-valid status
        if [ "$status" = "statusInvalid" ] || [ "$status" = "statusError" ] || [ "$status" = "invalid" ] || [ "$status" = "error" ]; then
            local filename=$(echo "$line" | jq -r '.filename // "unknown"' 2>/dev/null)
            local msg=$(echo "$line" | jq -r '.msg // "validation error"' 2>/dev/null)

            # Log critical schema violations
            log_error "Kubeconform validation failed: $filename - $msg"
            HIGH_IMPACT_ERRORS+=("CRITICAL_SCHEMA_ERROR: $filename - $msg")
        fi
    done < <(jq -c 'if type == "array" then .[] else . end' "$output_file" 2>/dev/null || cat "$output_file" 2>/dev/null)

    # Also check for non-JSON error output (kubeconform may output plain text errors)
    if grep -qi "error\|invalid\|missing required" "$output_file" 2>/dev/null; then
        local error_text=$(grep -i "error\|invalid\|missing required" "$output_file" 2>/dev/null | head -5)
        if [ -n "$error_text" ]; then
            log_error "Kubeconform raw error output detected"
            HIGH_IMPACT_ERRORS+=("VALIDATION_ERROR: $error_text")
        fi
    fi
}

classify_pluto_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    # Parse Pluto output
    while IFS= read -r line; do
        local removed=$(echo "$line" | jq -r '.removed // false' 2>/dev/null)
        local deprecated=$(echo "$line" | jq -r '.deprecated // false' 2>/dev/null)
        local name=$(echo "$line" | jq -r '.name // "unknown"' 2>/dev/null)
        local kind=$(echo "$line" | jq -r '.kind // "unknown"' 2>/dev/null)
        local version=$(echo "$line" | jq -r '.version // "unknown"' 2>/dev/null)
        local replacement=$(echo "$line" | jq -r '.replacementAPI // "none"' 2>/dev/null)

        if [ "$removed" = "true" ]; then
            # Removed APIs are HIGH IMPACT
            HIGH_IMPACT_ERRORS+=("REMOVED_API: $kind/$name uses removed API $version (replace with $replacement)")
        elif [ "$deprecated" = "true" ]; then
            # Deprecated (but not removed) are LOW IMPACT warnings
            LOW_IMPACT_ERRORS+=("DEPRECATED_API: $kind/$name uses deprecated API $version (replace with $replacement)")
        fi
    done < <(jq -c '.items[]?' "$output_file" 2>/dev/null || true)
}

classify_kubelinter_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    # KubeLinter checks to classify as HIGH IMPACT (security critical)

    local HIGH_IMPACT_CHECKS="host-network host-pid host-ipc privileged-container"

    # Checks that can be auto-fixed (LOW IMPACT)
    local LOW_IMPACT_CHECKS="no-read-only-root-fs unset-cpu-requirements unset-memory-requirements latest-tag drop-net-raw-capability"

    while IFS= read -r line; do
        local check=$(echo "$line" | jq -r '.Check // empty' 2>/dev/null)
        local object=$(echo "$line" | jq -r '.Object.K8sObject.Name // "unknown"' 2>/dev/null)
        local message=$(echo "$line" | jq -r '.Diagnostic.Message // "check failed"' 2>/dev/null)

        if [ -z "$check" ]; then
            continue
        fi
        
        if echo "$HIGH_IMPACT_CHECKS" | grep -qw "$check"; then
            HIGH_IMPACT_ERRORS+=("SECURITY: $check on $object - $message")
        elif echo "$LOW_IMPACT_CHECKS" | grep -qw "$check"; then
            LOW_IMPACT_ERRORS+=("BEST_PRACTICE: $check on $object - $message")
        fi
    done < <(jq -c '.Reports[]?' "$output_file" 2>/dev/null || true)
}

generate_error_report() {
    local severity="$1"
    shift
    local errors=("$@")

    local errors_json="[]"
    for err in "${errors[@]}"; do
        errors_json=$(echo "$errors_json" | jq --arg e "$err" '. += [$e]')
    done

    cat > /tmp/validation-report.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "severity": "$severity",
    "errors": $errors_json,
    "app_name": "${ARGOCD_APP_NAME:-unknown}",
    "source_repo": "${ARGOCD_APP_SOURCE_REPO_URL:-unknown}",
    "source_path": "${ARGOCD_APP_SOURCE_PATH:-unknown}",
    "revision": "${ARGOCD_APP_REVISION:-unknown}"
}
EOF
}

export -f log_info log_warn log_error
export -f classify_kubeconform_errors classify_pluto_errors classify_kubelinter_errors
export -f generate_error_report
