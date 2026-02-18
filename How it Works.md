# Manifest Validator CMP — How It Works

This is an **ArgoCD Config Management Plugin (CMP)** that validates Kubernetes manifests during deployment and takes automated corrective action based on error severity.

## How It Works

### Entry Point

ArgoCD invokes `scripts/validate.sh` as a sidecar container whenever an Application using this plugin syncs. The plugin runs inside a custom Docker image containing four validation tools: **Kubeconform**, **Pluto**, **KubeLinter**, and **Kyverno**.

### Validation Pipeline

The flow has four stages:

**1. Collect YAML files** — Finds all `*.yaml`/`*.yml` files, excluding `kustomization.yaml` and hidden files.

**2. Run three validation tools in parallel:**

| Tool | Purpose |
|------|---------|
| **Kubeconform** | Schema validation against K8s v1.28.0 OpenAPI specs |
| **Pluto** | Detects deprecated/removed API versions targeting K8s v1.29.0 |
| **KubeLinter** | Security and best-practice checks (configured in `config/kube-linter.yaml`) |

**3. Classify errors** — `scripts/utils.sh` parses the JSON output from each tool and sorts findings into two buckets:

- **HIGH impact** — Schema failures, removed APIs, and security violations (privileged containers, host network/PID/IPC, running as root, dangerous capabilities)
- **LOW impact** — Deprecated (but still functional) APIs and missing best practices (no probes, no resource limits, writable root FS, `latest` tag, etc.)

**4. Act based on severity:**

```
HIGH impact errors found?
  └─ YES → Log errors, generate report, git revert the commit, exit 1
              (ArgoCD blocks the deployment)

LOW impact errors found?
  └─ YES → Apply Kyverno mutation policies to auto-fix manifests,
           output fixed manifests to stdout, exit 0
           (ArgoCD deploys the corrected versions)

No errors?
  └─ Output original manifests to stdout, exit 0
```

### Auto-Fix Policies (`policies/`)

When low-impact issues are found, Kyverno applies five mutation policies to patch the manifests:

- `add-labels.yaml` — Adds `app.kubernetes.io/managed-by: argocd`
- `add-resource-limits.yaml` — Sets CPU (100m/500m) and memory (128Mi/256Mi) requests/limits
- `set-image-pull-policy.yaml` — Sets `imagePullPolicy: IfNotPresent`
- `add-probes.yaml` — Adds liveness/readiness probes (TCP port 8080)
- `set-security-context.yaml` — Sets `runAsNonRoot`, drops all capabilities, disables privilege escalation

### Git Rollback (`scripts/git-rollback.sh`)

For high-impact errors, the plugin clones the repo via SSH, creates a revert commit with a detailed message listing all validation errors, and pushes it back to the branch. This prevents the bad manifests from being retried.

### Deployment

The validator runs as a sidecar container in the ArgoCD repo-server pod, configured via `k8s/argocd-patch.yaml`. ConfigMaps provide the plugin registration, KubeLinter config, and git credentials. An SSH key secret enables the git rollback capability.
