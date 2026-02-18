#!/bin/bash
set -uo pipefail

source /home/argocd/scripts/utils.sh

WORK_DIR="$1"
CONFIG_FILE="/home/argocd/config/kube-linter.yaml"

if [ -f "$CONFIG_FILE" ]; then
    kube-linter lint "$WORK_DIR" --config "$CONFIG_FILE" --format json
else
    kube-linter lint "$WORK_DIR" --format json
fi
