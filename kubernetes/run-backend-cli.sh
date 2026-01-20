#!/bin/bash
# Helper script to run backend CLI commands using Kubernetes Job
# Usage: ./run-backend-cli.sh <command>
# Example: ./run-backend-cli.sh "python manage.py migrate"

set -e

NAMESPACE="${NAMESPACE:-automated}"
IMAGE="${BACKEND_IMAGE:-maborak/platform:apt-backend-0.1}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-test-apt}"
TIMESTAMP=$(date +%s)
JOB_NAME="backend-cli-${TIMESTAMP}"

if [ -z "$1" ]; then
  echo "Usage: $0 <command>"
  echo "Example: $0 'python manage.py migrate'"
  echo "Example: $0 'python -m alembic upgrade head'"
  exit 1
fi

COMMAND="$1"

echo "Creating Job: $JOB_NAME"
echo "Command: $COMMAND"
echo "Image: $IMAGE"
echo "Namespace: $NAMESPACE"
echo ""

# Get the backend pod to extract environment variables and secrets
BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$BACKEND_POD" ]; then
  echo "Warning: No backend pod found. Using default configuration."
  echo "You may need to update the Job YAML with correct environment variables."
fi

# Create Job YAML
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: apt
    app.kubernetes.io/component: backend-cli
    app.kubernetes.io/managed-by: manual
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: apt
        app.kubernetes.io/component: backend-cli
    spec:
      serviceAccountName: ${SERVICE_ACCOUNT}
      restartPolicy: Never
      containers:
      - name: backend
        image: ${IMAGE}
        imagePullPolicy: Always
        workingDir: /app
        command: ["/bin/sh", "-c"]
        args:
        - |
          set -e
          echo "Starting backend CLI command..."
          echo "Command: ${COMMAND}"
          echo "---"
          ${COMMAND}
          echo "---"
          echo "Command completed successfully"
        env:
        - name: PYTHONPATH
          value: "/app"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: test-apt-db-secret
              key: postgres-password
        - name: APT_BACKEND_JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: test-apt-backend-secret
              key: jwt-secret
        - name: APT_BACKEND_DATABASE_URL
          value: "postgresql://postgres:\$(POSTGRES_PASSWORD)@test-apt-db:5432/amazon_watcher"
        - name: APT_BACKEND_DB_ECHO
          value: "false"
        - name: APT_BACKEND_DB_ECHO_POOL
          value: "false"
        - name: APT_BACKEND_DB_POOL_SIZE
          value: "20"
        - name: APT_BACKEND_DB_MAX_OVERFLOW
          value: "30"
        - name: APT_BACKEND_DB_POOL_TIMEOUT
          value: "30"
        - name: APT_BACKEND_DB_POOL_RECYCLE
          value: "3600"
        - name: APT_BACKEND_DB_USE_REPLICA_ENGINE
          value: "false"
        - name: APT_BACKEND_UVI_HOST
          value: "0.0.0.0"
        - name: APT_BACKEND_UVI_PORT
          value: "9000"
        - name: APT_BACKEND_RELOAD
          value: "false"
        - name: APT_BACKEND_LOG_LEVEL
          value: "info"
        - name: APT_BACKEND_DEBUG_MODE
          value: "false"
        - name: APT_BACKEND_UVI_ACCESS_LOG
          value: "true"
        - name: APT_BACKEND_UVI_WORKERS
          value: "5"
        - name: APT_BACKEND_UVI_LIMIT_CONCURRENCY
          value: "100"
        - name: APT_BACKEND_UVI_LIMIT_MAX_REQUESTS
          value: "1000"
        - name: APT_BACKEND_UVI_TIMEOUT_KEEP_ALIVE
          value: "30"
        - name: APT_BACKEND_UVI_TIMEOUT_GRACEFUL_SHUTDOWN
          value: "30"
        - name: APT_BACKEND_JWT_ALGORITHM
          value: "HS256"
        - name: APT_BACKEND_JWT_ACCESS_TOKEN_EXPIRY
          value: "3600"
        - name: APT_BACKEND_JWT_REFRESH_TOKEN_EXPIRY
          value: "2592000"
        - name: APT_BACKEND_CORS_ORIGINS
          value: "*"
        - name: APT_BACKEND_CORS_ALLOW_CREDENTIALS
          value: "true"
        - name: APT_BACKEND_CORS_ALLOW_METHODS
          value: "*"
        - name: APT_BACKEND_CORS_ALLOW_HEADERS
          value: "*"
        - name: APT_BACKEND_CORS_EXPOSE_HEADERS
          value: ""
        - name: APT_BACKEND_CORS_MAX_AGE
          value: "600"
        - name: APT_BACKEND_RATE_LIMIT_ENABLED
          value: "true"
        - name: APT_BACKEND_RATE_LIMIT_REQUESTS
          value: "20"
        - name: APT_BACKEND_RATE_LIMIT_WINDOW
          value: "60"
        - name: APT_BACKEND_RATE_LIMIT_BYPASS_KEY
          value: ""
        - name: APT_BACKEND_RATE_LIMIT_EXCLUDED_PATHS
          value: "/docs,/redoc,/openapi.json,/favicon.ico,/health"
        - name: APT_BACKEND_RATE_LIMIT_BYPASS_PATHS
          value: ""
        - name: APT_BACKEND_MONITOR_ENABLED
          value: "true"
        - name: APT_BACKEND_MONITOR_INTERVAL
          value: "3600"
        - name: APT_BACKEND_MONITOR_BATCH_SIZE
          value: "5"
        - name: APT_BACKEND_PRICE_HISTORY_PERIODIC_SECONDS
          value: "3600"
        - name: APT_BACKEND_DEFAULT_COUNTRY
          value: "BO"
        - name: APT_BACKEND_HTTP_ENGINE
          value: "requests"
        - name: APT_BACKEND_HTTP_TIMEOUT
          value: "10.0"
        - name: APT_BACKEND_HTTP_RETRIES
          value: "1"
        - name: APT_BACKEND_HTTP_MAX_CONNECTIONS
          value: "10"
        - name: APT_BACKEND_SCREENSHOT_ENABLED
          value: "true"
        - name: APT_BACKEND_SCREENSHOT_ON_PRICE_CHANGE_ONLY
          value: "false"
        - name: APT_BACKEND_SCREENSHOT_ON_CHANGES
          value: "false"
        - name: APT_BACKEND_SCREENSHOT_ALWAYS
          value: "true"
        - name: APT_BACKEND_SCREENSHOT_MAX_RETRIES
          value: "3"
        - name: APT_BACKEND_SCREENSHOT_STORAGE_PATH
          value: "./var/screenshots"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_URL
          value: "http://test-apt-screenshot.${NAMESPACE}.svc.cluster.local:3000/amazon/"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_WIDTH
          value: "1200"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_HEIGHT
          value: "960"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_FULL_PAGE
          value: "false"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_JAVASCRIPT_ENABLED
          value: "false"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_STOP_ON_CAPTCHA
          value: "false"
        - name: APT_BACKEND_SCREENSHOT_SERVICE_BROWSER_TYPE
          value: "chromium"
        - name: APT_BACKEND_BENCH_KEY
          value: ""
        - name: APT_BACKEND_TEST_MODE
          value: "false"
        resources:
          limits:
            memory: 1Gi
            cpu: 1000m
          requests:
            memory: 512Mi
            cpu: 500m
EOF

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
echo "Job will auto-delete after 1 hour (ttlSecondsAfterFinished: 3600)"

exit $EXIT_CODE
