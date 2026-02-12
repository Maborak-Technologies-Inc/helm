#!/bin/bash
# Install Argo Rollouts UI Extension for ArgoCD
# This script patches the ArgoCD server deployment to add the rollout extension

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/argocd-rollout-extension-patch.json"

echo "Installing Argo Rollouts UI Extension for ArgoCD..."
echo ""

# Check if patch file exists
if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: Patch file not found at $PATCH_FILE"
    exit 1
fi

# Check if ArgoCD server deployment exists
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "Error: ArgoCD server deployment not found in argocd namespace"
    echo "Please ensure ArgoCD is installed first"
    exit 1
fi

# Check if patch already applied
if kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.initContainers[*].name}' | grep -q "rollout-extension-installer"; then
    echo "✅ Argo Rollouts UI Extension already installed. Skipping patch."
    exit 0
fi

# Apply the patch
echo "Applying patch to argocd-server deployment..."
kubectl patch deployment argocd-server -n argocd --type='json' -p="$(cat "$PATCH_FILE")"

# Wait for rollout to complete
echo ""
echo "Waiting for ArgoCD server rollout to complete..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s

# Verify installation
echo ""
echo "Verifying installation..."
if kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.initContainers[*].name}' | grep -q "rollout-extension-installer"; then
    echo "✅ Rollout extension installer initContainer added successfully"
else
    echo "❌ Failed to verify initContainer installation"
    exit 1
fi

# Check pod status
echo ""
echo "Checking ArgoCD server pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=60s

echo ""
echo "✅ Argo Rollouts UI Extension installed successfully!"
echo ""
echo "Next steps:"
echo "1. Hard refresh your browser (Ctrl+Shift+R or Cmd+Shift+R)"
echo "2. Navigate to a Rollout resource in ArgoCD UI"
echo "3. Click the 'ROLLOUT' tab to view the extension"
echo ""
