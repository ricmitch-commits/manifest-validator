#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

# Error details passed as arguments
ERRORS=("$@")

# Git configuration
GIT_SSH_KEY="${GIT_SSH_KEY_PATH:-/home/argocd/.ssh/id_rsa}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-argocd-cmp@openshift.local}"
GIT_USER_NAME="${GIT_USER_NAME:-ArgoCD CMP Validator}"
REPO_URL="${ARGOCD_APP_SOURCE_REPO_URL:-}"
TARGET_REVISION="${ARGOCD_APP_SOURCE_TARGET_REVISION:-main}"

# Validate required environment
if [ -z "$REPO_URL" ]; then
    log_error "ARGOCD_APP_SOURCE_REPO_URL not set, cannot perform rollback"
    exit 1
fi

if [ ! -f "$GIT_SSH_KEY" ]; then
    log_error "SSH key not found at $GIT_SSH_KEY, cannot perform rollback"
    exit 1
fi

log_info "Initiating git rollback for repository: $REPO_URL"

# Setup SSH with strict host key checking disabled for known hosts
export GIT_SSH_COMMAND="ssh -i $GIT_SSH_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/argocd/.ssh/known_hosts"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"

# Clone repository (shallow clone with 2 commits for revert)
log_info "Cloning repository..."
git clone --depth 2 --branch "$TARGET_REVISION" "$REPO_URL" repo || {
    log_error "Failed to clone repository"
    exit 1
}
cd repo

# Configure git
git config user.email "$GIT_USER_EMAIL"
git config user.name "$GIT_USER_NAME"

# Get current commit hash
CURRENT_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: $CURRENT_COMMIT"

# Check if we have a parent commit to revert to
if ! git rev-parse HEAD~1 >/dev/null 2>&1; then
    log_error "Cannot revert - no parent commit available"
    exit 1
fi

PREVIOUS_COMMIT=$(git rev-parse HEAD~1)
log_info "Rolling back to: $PREVIOUS_COMMIT"

# Format errors for commit message
ERRORS_TEXT=""
for err in "${ERRORS[@]}"; do
    ERRORS_TEXT="${ERRORS_TEXT}  - ${err}
"
done

# Generate rollback commit message
ROLLBACK_MSG="Rolled back from MANIFEST-VALIDATOR

Automatic rollback triggered by manifest-validator.

Validation errors detected:
${ERRORS_TEXT}
This rollback reverts changes that introduced critical validation errors:
- Schema validation failures
- Missing required fields
- Removed/deprecated API versions
- Critical security violations

Original commit: $CURRENT_COMMIT (${CURRENT_COMMIT:0:8})
App: ${ARGOCD_APP_NAME:-unknown}
Path: ${ARGOCD_APP_SOURCE_PATH:-unknown}
"

# Revert the commit
log_info "Creating revert commit..."
git revert --no-edit HEAD || {
    log_error "Failed to create revert commit"
    exit 1
}

# Amend with detailed message
git commit --amend -m "$ROLLBACK_MSG" || {
    log_error "Failed to amend commit message"
    exit 1
}

# Push the rollback
log_info "Pushing rollback commit to $TARGET_REVISION..."
git push origin "$TARGET_REVISION" || {
    log_error "Failed to push rollback commit"
    exit 1
}

log_info "Rollback commit pushed successfully"
