#!/bin/bash
set -e

NAMESPACE="automated"
APPS=""

# Parse arguments
for i in "$@"; do
  case $i in
    --app=*)
      APPS="${i#*=}"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${i#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

if [ -z "$APPS" ]; then
  echo "Usage: $0 --app=app1,app2,app3 [--namespace=automated]"
  exit 1
fi

# Function to check a single app
check_app() {
  local APP_NAME=$1
  local MISMATCH_FOUND=false
  local FIRST_JWT=""

  echo "---------------------------------------------------"
  echo "Checking JWT for App: $APP_NAME..."

  # Get list of relevant pods
  # Using Regex to match component label values: backend, backend-cli, backend-cronjob
  PODS=$(kubectl get pods -n $NAMESPACE -l "app.kubernetes.io/instance=$APP_NAME,app.kubernetes.io/component in (backend, backend-cli, backend-cronjob)" -o jsonpath='{.items[*].metadata.name}')

  if [ -z "$PODS" ]; then
    echo "⚠️  No pods found for app: $APP_NAME. Skipping."
    return 0
  fi

  for POD in $PODS; do
    # Check status
    STATUS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$STATUS" != "Running" ]; then
      echo "⚠️  Pod $POD is in state $STATUS. Skipping."
      continue
    fi

    echo -n "🔍 Checking $POD... "
    # Explicitly specify container to avoid "Defaulted container" message
    # Try backend first (for backend pods), then backend-cli (for CLI pods), then backend-cronjob
    # Use printenv for more reliable extraction (directly gets the variable value)
    JWT=""
    # Try each container in order, stopping when we find a value
    for CONTAINER in "backend" "backend-cli" "backend-cronjob" ""; do
      if [ -z "$CONTAINER" ]; then
        # Last attempt: no container specified (kubectl will default)
        JWT=$(kubectl exec -n $NAMESPACE $POD -- sh -c 'printenv APT_BACKEND_JWT_SECRET' 2>/dev/null | tr -d '\r\n' || echo "")
      else
        JWT=$(kubectl exec -n $NAMESPACE $POD -c "$CONTAINER" -- sh -c 'printenv APT_BACKEND_JWT_SECRET' 2>/dev/null | tr -d '\r\n' || echo "")
      fi
      if [ -n "$JWT" ]; then
        break
      fi
    done

    if [ -z "$JWT" ]; then
      echo "❌ NO JWT FOUND"
      MISMATCH_FOUND=true
    else
      if [ -z "$FIRST_JWT" ]; then
        FIRST_JWT="$JWT"
        echo "✅ OK (Ref: ${JWT:0:10}...)"
      else
        if [ "$JWT" == "$FIRST_JWT" ]; then
          echo "✅ OK"
        else
          echo "❌ MISMATCH! Found: ${JWT:0:10}..."
          MISMATCH_FOUND=true
        fi
      fi
    fi
  done

  if [ "$MISMATCH_FOUND" = true ]; then
    echo "🚨 FAIL: JWT Mismatches detected for $APP_NAME!"
    return 1
  else
    echo "🎉 SUCCESS: $APP_NAME is consistent."
    return 0
  fi
}

# Main Execution Loop
GLOBAL_FAIL=0
IFS=',' read -ra APP_ARRAY <<< "$APPS"
for APP in "${APP_ARRAY[@]}"; do
  if ! check_app "$APP"; then
    GLOBAL_FAIL=1
  fi
done

echo "==================================================="
if [ $GLOBAL_FAIL -eq 0 ]; then
  echo "✅ ALL CHECKS PASSED"
  exit 0
else
  echo "❌ SOME CHECKS FAILED (See above)"
  exit 1
fi
