#!/bin/bash

# Default values
APP_NAME=""
APP_NAMESPACE="argocd"
DISABLE=false
DRY_RUN=false
NAMESPACE_FILTER=""

# Usage function
usage() {
    echo "Usage: $0 --app <app-name> [--app-namespace <ns>] [--namespace <ns>] [--disable] [--dry-run]"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --app) APP_NAME="$2"; shift ;;
        --app=*) APP_NAME="${1#*=}" ;;
        --app-namespace) APP_NAMESPACE="$2"; shift ;;
        --app-namespace=*) APP_NAMESPACE="${1#*=}" ;;
        --namespace|-n) NAMESPACE_FILTER="$2"; shift ;;
        --namespace=*) NAMESPACE_FILTER="${1#*=}" ;;
        --disable) DISABLE=true ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate required arguments
if [ -z "$APP_NAME" ]; then
    echo "Error: --app is required."
    usage
fi

if [ "$DISABLE" = false ] && [ "$DRY_RUN" = false ]; then
    echo "Error: You must specify --disable to execute changes or --dry-run to simulate them."
    usage
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

echo "Processing ArgoCD App: $APP_NAME (Namespace: $APP_NAMESPACE)"
[ -n "$NAMESPACE_FILTER" ] && echo "Filtering resources by namespace: $NAMESPACE_FILTER"
[ "$DRY_RUN" = true ] && echo "Running in DRY-RUN mode. No changes will be applied."

# Get Application CR
APP_JSON=$(kubectl get application "$APP_NAME" -n "$APP_NAMESPACE" -o json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Could not find Application '$APP_NAME' in namespace '$APP_NAMESPACE'."
    exit 1
fi

# Function to perform action
perform_action() {
    local kind=$1
    local name=$2
    local ns=$3
    local replicas=0

    # Skip if namespace filter is set and doesn't match
    if [ -n "$NAMESPACE_FILTER" ] && [ "$ns" != "$NAMESPACE_FILTER" ]; then
        return
    fi

    case $kind in
        Deployment|StatefulSet)
            if [ "$DRY_RUN" = true ]; then
                current_replicas=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
                current_replicas=${current_replicas:-0} # Default to 0 if empty
                echo "[DRY-RUN] Would scale $kind $name in namespace $ns to 0 replicas (currently: $current_replicas)."
            else
                echo "Scaling $kind $name in namespace $ns to 0..."
                kubectl scale "$kind" "$name" -n "$ns" --replicas=0
            fi
            ;;
        Rollout)
            if [ "$DRY_RUN" = true ]; then
                current_replicas=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
                current_replicas=${current_replicas:-0}
                echo "[DRY-RUN] Would scale Rollout $name in namespace $ns to 0 replicas (currently: $current_replicas)."
            else
                echo "Scaling Rollout $name in namespace $ns to 0..."
                # Rollouts also use kubectl scale
                kubectl scale "$kind" "$name" -n "$ns" --replicas=0
            fi
            ;;
        CronJob)
            if [ "$DRY_RUN" = true ]; then
                # CronJobs use .spec.suspend
                is_suspended=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.suspend}' 2>/dev/null)
                is_suspended=${is_suspended:-false}
                echo "[DRY-RUN] Would suspend CronJob $name in namespace $ns (currently suspended: $is_suspended)."
            else
                echo "Suspending CronJob $name in namespace $ns..."
                kubectl patch cronjob "$name" -n "$ns" -p '{"spec" : {"suspend" : true }}'
            fi
            ;;
    esac
}

# Extract and process resources
# We filter for relevant kinds from status.resources
echo "$APP_JSON" | jq -c '.status.resources[] | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "CronJob" or .kind == "Rollout")' | while read -r resource; do
    kind=$(echo "$resource" | jq -r '.kind')
    name=$(echo "$resource" | jq -r '.name')
    ns=$(echo "$resource" | jq -r '.namespace')

    perform_action "$kind" "$name" "$ns"
done

echo "Done."
