# Manifest Validator CMP for ArgoCD

A Config Management Plugin (CMP) for ArgoCD/OpenShift GitOps that validates Kubernetes manifests, auto-fixes low-impact issues, and triggers git rollbacks for critical errors.

## Features

- **Schema Validation** (Kubeconform) - Validates manifests against Kubernetes API schemas
- **Deprecated API Detection** (Pluto) - Detects removed and deprecated API versions
- **Best Practices** (KubeLinter) - Checks security and configuration best practices
- **Auto-Fix** (Kyverno) - Automatically fixes low-impact issues
- **Git Rollback** - Pushes revert commits for critical errors

## Severity Classification

| Category | Error Type | Impact | Action |
|----------|------------|--------|--------|
| Kubeconform | Schema validation failure | HIGH | Git Rollback |
| Pluto | Removed API version | HIGH | Git Rollback |
| Pluto | Deprecated API version | LOW | Warning |
| KubeLinter | privileged-container, host-network | HIGH | Git Rollback |
| KubeLinter | missing-probes, unset-resources | LOW | Auto-fix |

## Auto-Fix Policies

The following are automatically fixed:
- Missing `app.kubernetes.io/managed-by` labels
- Missing resource requests/limits (defaults: 100m-500m CPU, 128Mi-256Mi memory)
- Missing `imagePullPolicy` (defaults to `IfNotPresent`)
- Missing liveness/readiness probes (TCP socket on port 8080)
- Missing security context (runAsNonRoot, drop ALL capabilities)

## Prerequisites

- OpenShift GitOps or ArgoCD installed
- Podman installed locally
- SSH key with write access to your Git repository

## Installation

### 1. Build and Push Container Image to OpenShift Internal Registry

```bash
cd manifest-validator

# Login to OpenShift
oc login -u kubeadmin https://api.crc.testing:6443

# Expose the internal registry (if not already exposed)
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}'

# Create the BuildConfig (if not already applied)
oc apply -f k8s/buildconfig.yaml -n openshift-gitops

# Trigger the build — uploads your local source into the cluster and builds there.
oc start-build manifest-validator --from-dir=. -n openshift-gitops --follow

#Validate the build is there
oc get imagestream manifest-validator -n openshift-gitops
```

**Alternative: Use local registry for CRC**

```bash
# For CRC, you can also use the internal service URL directly
podman build -t default-route-openshift-image-registry.apps-crc.testing/openshift-gitops/manifest-validator:v1.0.0 .
podman push --tls-verify=false default-route-openshift-image-registry.apps-crc.testing/openshift-gitops/manifest-validator:v1.0.0
```

### 2. Add SSH Key for Git Rollbacks

```bash
# Update the secret file with your private SSH  key
cp k8s/secret-ssh-key-template.yaml k8s/secret-ssh-key.yaml
# Edit k8s/secret-ssh-key.yaml and replace <YOUR_SSH_PRIVATE_KEY_HERE>
```

### 3. Deploy Kubernetes Resources

```bash
# Apply ConfigMaps
kubectl apply -f k8s/configmap-plugin.yaml
kubectl apply -f k8s/configmap-kube-linter.yaml
kubectl apply -f k8s/configmap-git.yaml

# Apply Secret (after adding your SSH key)
kubectl apply -f k8s/secret-ssh-key.yaml

# Patch ArgoCD to add the CMP sidecar
kubectl patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file k8s/argocd-patch.yaml
```

### 4. Wait for Rollout

```bash
kubectl rollout status deployment/openshift-gitops-repo-server -n openshift-gitops
```

### 5. To Remove the sidecar

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file k8s/argocd-remove.yaml
```

## Usage

### Create an Application Using the Plugin

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: openshift-gitops
spec:
  source:
    plugin:
      name: manifest-validator
    repoURL: git@github.com:your-org/your-repo.git
    path: manifests/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-ns
```

See `k8s/example-application.yaml` for a complete example.

## Verification

### Check Sidecar is Running

```bash
kubectl get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-repo-server \
  -o jsonpath='{.items[*].spec.containers[*].name}'
```

### View CMP Logs

```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator -f
```

### Test Validation

1. **Valid manifests** - Should pass through with fixes applied
2. **Missing labels** - Should auto-fix and apply
3. **Invalid schema** - Should trigger rollback commit

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBERNETES_VERSION` | `1.28.0` | K8s version for schema validation |
| `TARGET_KUBERNETES_VERSION` | `v1.29.0` | Target K8s version for API deprecation |
| `GIT_USER_EMAIL` | `argocd-cmp@openshift.local` | Email for rollback commits |
| `GIT_USER_NAME` | `ArgoCD CMP Validator` | Name for rollback commits |

### Customizing Policies

Edit the Kyverno policies in `policies/` to customize auto-fix behavior:
- `add-labels.yaml` - Default labels
- `add-resource-limits.yaml` - Default resources
- `set-image-pull-policy.yaml` - Image pull policy
- `add-probes.yaml` - Health probes
- `set-security-context.yaml` - Security context

### Customizing KubeLinter Rules

Edit `config/kube-linter.yaml` to enable/disable specific checks.

## Troubleshooting

### Plugin Not Discovered

Check that the plugin configuration is mounted correctly:
```bash
kubectl exec -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator \
  -- cat /home/argocd/cmp-server/config/plugin.yaml
```

### Git Rollback Failing

1. Verify SSH key is mounted:
   ```bash
   kubectl exec -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator \
     -- ls -la /home/argocd/.ssh/
   ```

2. Test SSH connectivity:
   ```bash
   kubectl exec -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator \
     -- ssh -T git@github.com
   ```

### Validation Tools Missing

Check init logs:
```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator | head -20
```

## License

MIT
