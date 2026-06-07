#!/bin/bash
# Helper script to run one-time backend CLI commands in a Rollout pod
# This executes commands in an existing CLI pod using kubectl exec
# Usage: ./run-backend-cli-helm.sh <command>
# Example: ./run-backend-cli-helm.sh "python manage.py migrate"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-automated}"
RELEASE_NAME="${RELEASE_NAME:-test-apt}"

if [ -z "$1" ]; then
  echo "Usage: $0 <command>"
  echo "Example: $0 'python manage.py migrate'"
  echo "Example: $0 'python -m alembic upgrade head'"
  echo ""
  echo "This script executes commands in an existing CLI Rollout pod."
  echo "Make sure backend.cli.enabled=true in your Helm values."
  exit 1
fi

COMMAND="$1"

echo "Finding CLI Rollout pods..."
# Get CLI pods
CLI_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend-cli -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$CLI_PODS" ]; then
  echo "❌ Error: No CLI pods found in namespace $NAMESPACE"
  echo "Please ensure backend.cli.enabled=true in your Helm values."
  echo "The CLI Rollout must be running to execute commands."
  exit 1
fi

# Get the first ready pod
READY_POD=""
for pod in $CLI_PODS; do
  STATUS=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  if [ "$STATUS" = "True" ]; then
    READY_POD=$pod
    break
  fi
done

if [ -z "$READY_POD" ]; then
  echo "❌ Error: No ready CLI pods found"
  echo "Waiting for CLI pods to be ready..."
  kubectl wait --for=condition=ready pod -n $NAMESPACE -l app.kubernetes.io/component=backend-cli --timeout=60s || {
    echo "❌ CLI pods are not ready. Aborting."
    exit 1
  }
  # Try again after waiting
  READY_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend-cli -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$READY_POD" ]; then
  echo "❌ Error: Could not find a ready CLI pod"
  exit 1
fi

echo "✅ Using CLI pod: $READY_POD"
echo "Command: $COMMAND"
echo ""
echo "Executing command in pod..."
echo "---"

# Execute the command in the pod
kubectl exec -n $NAMESPACE $READY_POD -c backend-cli -- /bin/sh -c "cd /app && $COMMAND"

EXIT_CODE=$?

echo "---"
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ Command completed successfully!"
else
  echo "❌ Command failed with exit code $EXIT_CODE"
fi

echo ""
echo "To view pod logs: kubectl logs -n $NAMESPACE $READY_POD -c backend-cli"
echo "To exec into pod: kubectl exec -it -n $NAMESPACE $READY_POD -c backend-cli -- /bin/sh"

exit $EXIT_CODE
