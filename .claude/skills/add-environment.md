# Skill: Add Environment / Namespace

Workflow for adding a new deployment environment (namespace) to the Argo CD GitOps setup.

## Prerequisites

- Know the environment name (e.g., `qa`, `canary`, `demo`)
- Know the sync policy (auto-sync for non-production, manual for production)
- Read `docs/` for existing Argo CD Application setup scripts
- Read `CLAUDE.md` for the current namespace strategy (dev, staging, production, automated)

## Step 1 — Define Environment Values Override

Create `charts/amazon-watcher-stack/values-{env}.yaml`:

```yaml
# Environment-specific overrides for {env}
# Base values come from values.yaml — only override what differs

global:
  domain: "{env}.amazonwatcher.com"

backend:
  replicaCount: 1    # Adjust per environment
  image:
    tag: "{env}-latest"  # Or pinned SHA
  env:
    APT_BACKEND_LOG_LEVEL: "info"
    # Environment-specific env vars only

ui:
  replicaCount: 1
  image:
    tag: "{env}-latest"
  env:
    VITE_API_URL: "https://api.{env}.amazonwatcher.com"

database:
  storage:
    size: "5Gi"       # Smaller for non-production
```

Rules:
- Only override values that differ from defaults
- Never put secrets in values files — inject at deploy time
- Use the environment name in domain and image tags
- Keep non-production environments smaller (fewer replicas, less storage)

## Step 2 — Create Argo CD Application Script

Create `docs/setup-{env}-argocd.sh`:

```bash
#!/bin/bash
set -euo pipefail

NAMESPACE="{env}"
APP_NAME="amazon-watcher-{env}"
REPO_URL="https://maborak-technologies-inc.github.io/helm"
CHART="amazon-watcher-stack"
PROJECT="amazon-watcher"

echo "Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Argo CD Application: ${APP_NAME}..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
spec:
  project: ${PROJECT}
  source:
    repoURL: ${REPO_URL}
    chart: ${CHART}
    targetRevision: "*"    # Or pin to specific version
    helm:
      valueFiles:
        - values.yaml
        - values-{env}.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
    - group: argoproj.io
      kind: Rollout
      jsonPointers:
        - /spec/replicas
EOF

echo "Done. Verify with: argocd app get ${APP_NAME}"
```

### For production-like environments, use manual sync:

Replace `syncPolicy.automated` with:
```yaml
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
  # No automated sync — requires manual sync or approval
```

## Step 3 — Update CLAUDE.md

Add the new namespace to the deployment model section:
- Add to the namespaces list
- Note the sync policy (auto or manual)
- Document any environment-specific configuration

## Step 4 — Validate

```bash
# Verify values override renders correctly
helm template test charts/amazon-watcher-stack \
  -f charts/amazon-watcher-stack/values.yaml \
  -f charts/amazon-watcher-stack/values-{env}.yaml

# Lint with override
helm lint charts/amazon-watcher-stack \
  -f charts/amazon-watcher-stack/values.yaml \
  -f charts/amazon-watcher-stack/values-{env}.yaml
```

## Verification Checklist

- [ ] Values override file created with only environment-specific differences
- [ ] No secrets in values override file
- [ ] Argo CD Application script created
- [ ] Sync policy matches environment risk level (auto for dev, manual for prod-like)
- [ ] `ignoreDifferences` includes `/spec/replicas` for HPA compatibility
- [ ] Argo CD project isolates this environment
- [ ] Namespace documented in CLAUDE.md
- [ ] `helm template` with override renders correctly
- [ ] `helm lint` with override passes
