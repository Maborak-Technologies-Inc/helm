#!/bin/bash
# Helper script to run backend CLI commands using Helm template
# This ensures the Job uses the same environment variables as the backend rollout
# Usage: ./run-backend-cli-helm.sh <command>
# Example: ./run-backend-cli-helm.sh "python manage.py migrate"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../charts/amazon-watcher-stack"
NAMESPACE="${NAMESPACE:-automated}"
RELEASE_NAME="${RELEASE_NAME:-test-apt}"

if [ -z "$1" ]; then
  echo "Usage: $0 <command>"
  echo "Example: $0 'python manage.py migrate'"
  echo "Example: $0 'python -m alembic upgrade head'"
  exit 1
fi

COMMAND="$1"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

echo "Checking if backend is ready..."
# Check if backend pods exist and are ready
BACKEND_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$BACKEND_PODS" ]; then
  echo "❌ Error: No backend pods found in namespace $NAMESPACE"
  echo "Please ensure backend is deployed first."
  exit 1
fi

READY_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' 2>/dev/null || echo "")

if [ -z "$READY_PODS" ]; then
  echo "❌ Error: No ready backend pods found"
  echo "Waiting for backend pods to be ready..."
  kubectl wait --for=condition=ready pod -n $NAMESPACE -l app.kubernetes.io/component=backend --timeout=60s || {
    echo "❌ Backend pods are not ready. Aborting."
    exit 1
  }
fi

echo "✅ Backend is ready"
echo ""

echo "Creating backend CLI Job using Helm template..."
echo "Command: $COMMAND"
echo "Release: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Generate Job YAML using Helm template with the command
helm template $RELEASE_NAME $CHART_DIR \
  --set backend.cliJob.enabled=true \
  --set backend.cliJob.command="$COMMAND" \
  --set backend.cliJob.timestamp="$TIMESTAMP" \
  --namespace $NAMESPACE \
  -s templates/backend-cli-job.yaml | kubectl apply -f -

JOB_NAME="${RELEASE_NAME}-backend-cli-${TIMESTAMP}"

echo ""
echo "Job created: $JOB_NAME"
echo "Waiting for Job to start..."
sleep 2

# Wait for pod to be created
POD_NAME=""
for i in {1..30}; do
  POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$POD_NAME" ]; then
    break
  fi
  sleep 1
done

if [ -z "$POD_NAME" ]; then
  echo "Error: Pod not created. Check Job status:"
  kubectl describe job $JOB_NAME -n $NAMESPACE
  exit 1
fi

echo "Pod: $POD_NAME"
echo ""
echo "Following logs (Ctrl+C to stop following, job will continue):"
echo "---"
kubectl logs -f -n $NAMESPACE $POD_NAME || true

echo ""
echo "Waiting for Job to complete..."
kubectl wait --for=condition=complete --timeout=600s job/$JOB_NAME -n $NAMESPACE 2>/dev/null || true

# Check final status
JOB_STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")

if [ "$JOB_STATUS" = "True" ]; then
  echo "✅ Job completed successfully!"
  EXIT_CODE=0
else
  echo "❌ Job failed or is still running"
  echo "Job status:"
  kubectl get job $JOB_NAME -n $NAMESPACE
  echo ""
  echo "Pod logs:"
  kubectl logs -n $NAMESPACE $POD_NAME || true
  EXIT_CODE=1
fi

echo ""
echo "To view logs later: kubectl logs -n $NAMESPACE $POD_NAME"
echo "To delete Job: kubectl delete job $JOB_NAME -n $NAMESPACE"
echo "Job will auto-delete after configured TTL"

exit $EXIT_CODE
