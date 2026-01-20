#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Default values (can be overridden with flags)
DEFAULT_NAMESPACE="automated"
DEFAULT_APP_NAME="prod"
DEFAULT_PROJECT_NAME="zabbix"
DEFAULT_REPO_URL="git@github.com:Maborak-Technologies-Inc/helm.git"
DEFAULT_CHART_PATH="charts/amazon-watcher-stack"
DEFAULT_SSH_KEY_PATH="${HOME}/.ssh/id_rsa_argocd"
ARGOCD_PORT=8080
API_PORT=9000

# Runtime variables
NAMESPACE=""
APP_NAME=""
PROJECT_NAME=""
REPO_URL=""
CHART_PATH=""
SSH_KEY_PATH=""
FORCE=false  # Force flag to delete/recreate existing resources

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check argocd CLI
    if ! command -v argocd &> /dev/null; then
        print_error "argocd CLI is not installed"
        exit 1
    fi
    
    # Check if logged into ArgoCD
    if ! argocd account get-user-info &> /dev/null; then
        print_warn "Not logged into ArgoCD. Attempting to login..."
        setup_argocd_access
    fi
    
    print_info "Prerequisites check passed"
}

setup_argocd_access() {
    print_info "Setting up ArgoCD access..."
    
    # Check if port-forward is needed
    if ! curl -s -k https://localhost:${ARGOCD_PORT} &> /dev/null; then
        print_info "Starting ArgoCD port-forward on port ${ARGOCD_PORT}..."
        kubectl port-forward svc/argocd-server -n argocd ${ARGOCD_PORT}:443 > /tmp/argocd-portforward.log 2>&1 &
        sleep 3
    fi
    
    # Get admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [ -z "$ARGOCD_PASSWORD" ]; then
        print_error "Could not retrieve ArgoCD admin password. Please login manually."
        exit 1
    fi
    
    # Login to ArgoCD
    print_info "Logging into ArgoCD..."
    argocd login localhost:${ARGOCD_PORT} --insecure --username admin --password "${ARGOCD_PASSWORD}" || {
        print_error "Failed to login to ArgoCD"
        exit 1
    }
    
    print_info "Successfully logged into ArgoCD"
}

wait_for_sync_completion() {
    local app_name=$1
    local timeout=${2:-60}
    local elapsed=0
    
    print_info "Checking for in-progress operations on '${app_name}'..."
    
    # Check if there's an operation in progress by trying to sync (which will fail if one is running)
    # First, try to get operation status from app info
    local app_info=$(argocd app get ${app_name} -o json 2>/dev/null || echo "")
    
    if [ -z "$app_info" ]; then
        print_warn "Could not get application info, assuming no operation in progress"
        return 0
    fi
    
    # Check for operation state in the JSON
    local operation_state=$(echo "$app_info" | grep -o '"operationState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    
    if [ -z "$operation_state" ] || [ "$operation_state" = "null" ]; then
        print_info "No operation in progress"
        return 0
    fi
    
    # If operation is running, wait for it
    if echo "$operation_state" | grep -qi "running"; then
        print_info "Operation in progress (state: ${operation_state}), waiting for completion..."
        while [ $elapsed -lt $timeout ]; do
            sleep 2
            elapsed=$((elapsed + 2))
            
            # Check again
            app_info=$(argocd app get ${app_name} -o json 2>/dev/null || echo "")
            operation_state=$(echo "$app_info" | grep -o '"operationState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
            
            if [ -z "$operation_state" ] || [ "$operation_state" = "null" ] || echo "$operation_state" | grep -qi "succeeded\|failed"; then
                print_info "Operation completed (state: ${operation_state})"
                return 0
            fi
            
            if [ $((elapsed % 10)) -eq 0 ]; then
                print_info "Still waiting... (${elapsed}s/${timeout}s)"
            fi
        done
        
        # Timeout reached
        print_warn "Timeout waiting for operation to complete. Attempting to terminate..."
        argocd app terminate-op ${app_name} 2>/dev/null || true
        sleep 3
    elif echo "$operation_state" | grep -qi "succeeded\|failed"; then
        print_info "Previous operation completed (state: ${operation_state})"
        return 0
    else
        # Unknown state, try to terminate
        print_warn "Unknown operation state: ${operation_state}. Attempting to terminate..."
        argocd app terminate-op ${app_name} 2>/dev/null || true
        sleep 3
    fi
    
    return 0
}

wait_for_app_synced() {
    local app_name=$1
    local timeout=${2:-120}
    local elapsed=0
    
    print_info "Waiting for application '${app_name}' to be synced..."
    
    while [ $elapsed -lt $timeout ]; do
        # Get sync status
        local sync_status=$(argocd app get ${app_name} -o json 2>/dev/null | grep -o '"sync":{"status":"[^"]*"' | head -1 | cut -d'"' -f6 || echo "")
        
        if [ "$sync_status" = "Synced" ]; then
            print_info "Application is synced"
            return 0
        fi
        
        # Also check if there's an operation in progress
        local operation_state=$(argocd app get ${app_name} -o json 2>/dev/null | grep -o '"operationState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
        
        if [ -n "$operation_state" ] && [ "$operation_state" != "null" ]; then
            if echo "$operation_state" | grep -qi "running"; then
                if [ $((elapsed % 10)) -eq 0 ]; then
                    print_info "Sync in progress... (${elapsed}s/${timeout}s)"
                fi
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $timeout ]; then
        print_warn "Timeout waiting for application to sync (waited ${timeout}s)"
        print_info "Application may still be syncing. Continuing..."
        return 1
    fi
    
    return 0
}

safe_sync_app() {
    local app_name=$1
    
    print_info "Preparing to sync '${app_name}'..."
    
    # Wait for any in-progress operations to complete
    wait_for_sync_completion ${app_name} 60
    
    # Attempt sync with retry logic
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        print_info "Attempting sync (attempt $((retry + 1))/${max_retries})..."
        
        # Capture both output and exit code
        if argocd app sync ${app_name} > /tmp/argocd-sync.log 2>&1; then
            cat /tmp/argocd-sync.log
            print_info "Sync initiated successfully"
            return 0
        else
            # Show the error
            cat /tmp/argocd-sync.log
            # Check if error is due to operation in progress
            if grep -q "another operation is already in progress" /tmp/argocd-sync.log 2>/dev/null; then
                retry=$((retry + 1))
                if [ $retry -lt $max_retries ]; then
                    print_warn "Operation in progress detected. Waiting and retrying..."
                    wait_for_sync_completion ${app_name} 30
                    sleep 2
                else
                    print_warn "Max retries reached. Attempting to terminate stuck operation..."
                    argocd app terminate-op ${app_name} 2>/dev/null || true
                    sleep 3
                    # One final attempt
                    if argocd app sync ${app_name} 2>/dev/null; then
                        print_info "Sync initiated after terminating stuck operation"
                        return 0
                    fi
                fi
            else
                # Different error, don't retry
                print_error "Sync failed with different error"
                return 1
            fi
        fi
    done
    
    print_error "Failed to sync after ${max_retries} attempts"
    return 1
}

install_amazon_watcher_backend() {
    print_info "Starting Amazon Watcher Backend installation..."
    
    # Step 1: Create namespace
    print_info "Creating namespace '${NAMESPACE}'..."
    kubectl create namespace ${NAMESPACE} 2>/dev/null || print_warn "Namespace '${NAMESPACE}' already exists"
    
    # Step 2: Verify ArgoCD project exists
    print_info "Verifying ArgoCD project '${PROJECT_NAME}'..."
    if argocd proj get ${PROJECT_NAME} &> /dev/null; then
        if [ "$FORCE" = true ]; then
            print_warn "Project '${PROJECT_NAME}' already exists. Deleting (--force enabled)..."
            argocd proj delete ${PROJECT_NAME} --yes || {
                print_error "Failed to delete existing project"
                exit 1
            }
            print_info "Creating project '${PROJECT_NAME}'..."
            argocd proj create ${PROJECT_NAME} --description "Amazon Watcher Backend project" || {
                print_error "Failed to create project"
                exit 1
            }
        else
            print_warn "Project '${PROJECT_NAME}' already exists"
            print_info "Skipping project creation. Use --force to delete and recreate it."
        fi
    else
        print_info "Creating ArgoCD project '${PROJECT_NAME}'..."
        argocd proj create ${PROJECT_NAME} --description "Amazon Watcher Backend project"
    fi
    
    # Add repository to project
    print_info "Adding repository to project..."
    argocd proj add-source ${PROJECT_NAME} ${REPO_URL} 2>/dev/null || print_warn "Repository may already be added to project"
    
    # Add destination namespace
    print_info "Adding destination namespace to project..."
    argocd proj add-destination ${PROJECT_NAME} https://kubernetes.default.svc ${NAMESPACE} 2>/dev/null || print_warn "Destination may already be added"
    
    # Step 3: Add repository to ArgoCD
    print_info "Adding repository to ArgoCD..."
    if ! argocd repo list | grep -q "${REPO_URL}"; then
        if [ -f "${SSH_KEY_PATH}" ]; then
            argocd repo add ${REPO_URL} --ssh-private-key-path ${SSH_KEY_PATH} || print_warn "Repository may already exist"
        else
            print_error "SSH key not found at ${SSH_KEY_PATH}"
            print_info "Please provide SSH key path with --ssh-key option"
            exit 1
        fi
    else
        print_info "Repository already added"
    fi
    
    # Step 4: Create ArgoCD application
    print_info "Creating ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        if [ "$FORCE" = true ]; then
            print_warn "Application '${APP_NAME}' already exists. Deleting it first (--force enabled)..."
            argocd app delete ${APP_NAME} --yes 2>/dev/null || kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
            print_info "Waiting for application deletion to complete..."
            sleep 3
            # Wait until application is actually gone (max 30 seconds)
            TIMEOUT=30
            ELAPSED=0
            while (argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null) && [ $ELAPSED -lt $TIMEOUT ]; do
                print_info "Waiting for application to be fully deleted... (${ELAPSED}s/${TIMEOUT}s)"
                sleep 2
                ELAPSED=$((ELAPSED + 2))
            done
            if [ $ELAPSED -ge $TIMEOUT ]; then
                print_warn "Application deletion taking longer than expected. Removing finalizers..."
                # Remove finalizers to allow deletion
                kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                sleep 2
                # Try force deletion
                kubectl delete application ${APP_NAME} -n argocd --force --grace-period=0 2>/dev/null || true
                sleep 3
            fi
        else
            print_error "Application '${APP_NAME}' already exists!"
            print_info "Use a different name or add --force to delete and recreate it."
            print_info "Example: $0 install --app ${APP_NAME}-new --force"
            exit 1
        fi
    fi
    
    # Create application with auto-sync enabled
    print_info "Creating ArgoCD application with auto-sync enabled..."
    
    # Build base command arguments
    BASE_ARGS=(
        --repo "${REPO_URL}"
        --path "${CHART_PATH}"
        --dest-name in-cluster
        --dest-namespace "${NAMESPACE}"
        --project "${PROJECT_NAME}"
        --sync-policy automated
        --self-heal
        --auto-prune
    )
    
    if ! argocd app create "${APP_NAME}" \
        "${BASE_ARGS[@]}" \
        --upsert 2>/dev/null; then
        # If upsert doesn't work, try without it (for older ArgoCD versions)
        print_info "Trying without upsert flag..."
        argocd app create "${APP_NAME}" \
            "${BASE_ARGS[@]}"
    fi
    
    # Step 5: Wait for auto-sync to complete (auto-sync is enabled, so no manual sync needed)
    print_info "Waiting for auto-sync to complete..."
    wait_for_app_synced ${APP_NAME} 120 || {
        print_warn "Auto-sync may still be in progress. Continuing to wait for pods..."
    }
    
    # Step 6: Wait for pods to be ready
    print_info "Waiting for pods to be ready..."
    HELM_RELEASE="amazon-watcher-stack${APP_NAME}"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE} -n ${NAMESPACE} --timeout=300s || print_warn "Pod not ready yet"
    
    # Display status
    print_info "Installation complete!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Amazon Watcher Backend Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access Amazon Watcher Backend API:${NC}"
    HELM_RELEASE="amazon-watcher-stack${APP_NAME}"
    echo ""
    echo -e "${GREEN}Option 1: Using kubectl proxy (Recommended - single command for all services)${NC}"
    echo "  1. Start kubectl proxy in a separate terminal:"
    echo -e "     ${GREEN}kubectl proxy${NC}"
    echo ""
    echo "  2. Access API via proxy:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/${NAMESPACE}/services/${HELM_RELEASE}:${API_PORT}/proxy/${NC}"
    echo ""
    echo "  3. Health endpoint:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/${NAMESPACE}/services/${HELM_RELEASE}:${API_PORT}/proxy/health${NC}"
    echo ""
    echo "  4. API documentation:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/${NAMESPACE}/services/${HELM_RELEASE}:${API_PORT}/proxy/docs${NC}"
    echo ""
    echo -e "${GREEN}Option 2: Using port-forward (Direct access)${NC}"
    echo "  1. Run port-forward in a separate terminal:"
    echo -e "     ${GREEN}kubectl port-forward svc/${HELM_RELEASE} -n ${NAMESPACE} ${API_PORT}:${API_PORT}${NC}"
    echo ""
    echo "  2. Open your browser and navigate to:"
    echo -e "     ${GREEN}http://localhost:${API_PORT}${NC}"
    echo ""
    echo "  3. Access endpoints:"
    echo -e "     • Health: ${GREEN}http://localhost:${API_PORT}/health${NC}"
    echo -e "     • API Docs: ${GREEN}http://localhost:${API_PORT}/docs${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} Keep the proxy or port-forward command running in a separate terminal."
    echo "      Press Ctrl+C in that terminal to stop it."
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • Check status: ${GREEN}kubectl get pods -n ${NAMESPACE}${NC}"
    echo -e "  • View ArgoCD app: ${GREEN}argocd app get ${APP_NAME}${NC}"
    echo -e "  • Sync app: ${GREEN}argocd app sync ${APP_NAME}${NC}"
    echo -e "  • View logs: ${GREEN}kubectl logs -n ${NAMESPACE} -l app=${HELM_RELEASE}${NC}"
    echo ""
}

uninstall_amazon_watcher_backend() {
    if [ "$FORCE" != true ]; then
        print_error "Uninstall requires --force flag for safety"
        print_info "Usage: $0 uninstall --force"
        print_warn "This will delete the ArgoCD application and all Amazon Watcher Backend resources!"
        exit 1
    fi
    
    print_warn "Starting Amazon Watcher Backend uninstallation (--force enabled)..."
    
    # Step 1: Delete ArgoCD application
    print_info "Deleting ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        # Try to delete via ArgoCD CLI first
        argocd app delete ${APP_NAME} --yes 2>/dev/null || true
        sleep 2
        
        # If still exists, try kubectl delete
        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
            sleep 2
        fi
        
        # If still exists and stuck, remove finalizers
        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            print_warn "Application deletion stuck, removing finalizers..."
            kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            sleep 2
            # Try deleting again after removing finalizers
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
        fi
        
        sleep 2
    else
        print_info "Application '${APP_NAME}' does not exist"
    fi
    
    # Step 2: Stop port-forward
    print_info "Stopping port-forward..."
    HELM_RELEASE="amazon-watcher-stack${APP_NAME}"
    pkill -f "port-forward.*${HELM_RELEASE}" 2>/dev/null || true
    
    # Step 3: Delete namespace (this will delete all resources)
    print_info "Deleting namespace '${NAMESPACE}'..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${NAMESPACE} --wait=true
        print_info "Waiting for namespace deletion to complete..."
        sleep 5
    else
        print_info "Namespace '${NAMESPACE}' does not exist"
    fi
    
    # Step 4: Verify cleanup
    print_info "Verifying cleanup..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_warn "Namespace still exists (may be in terminating state)"
    else
        print_info "Namespace deleted successfully"
    fi
    
    # Check for any remaining pods
    REMAINING_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -i "${APP_NAME}" | wc -l)
    if [ "${REMAINING_PODS}" -gt 0 ]; then
        print_warn "Found ${REMAINING_PODS} remaining pod(s)"
    else
        print_info "No Amazon Watcher Backend pods found"
    fi
    
    print_info "Uninstallation complete!"
}

show_status() {
    print_info "Amazon Watcher Backend Status:"
    echo ""
    
    # Check if application exists
    if argocd app get ${APP_NAME} &> /dev/null; then
        echo "ArgoCD Application:"
        argocd app get ${APP_NAME} | head -10
        echo ""
    else
        print_warn "Application '${APP_NAME}' does not exist"
    fi
    
    # Check pods
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        HELM_RELEASE="amazon-watcher-stack${APP_NAME}"
        echo "Pods:"
        kubectl get pods -n ${NAMESPACE} -l app=${HELM_RELEASE}
        echo ""
        
        echo "Services:"
        kubectl get svc -n ${NAMESPACE} -l app=${HELM_RELEASE}
        echo ""
        
        echo "PersistentVolumeClaims:"
        kubectl get pvc -n ${NAMESPACE} -l app=${HELM_RELEASE} 2>/dev/null || echo "  No PVCs found"
    else
        print_warn "Namespace '${NAMESPACE}' does not exist"
    fi
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app=*)
                APP_NAME="${1#*=}"
                shift
                ;;
            --app)
                APP_NAME="$2"
                shift 2
                ;;
            --namespace=*)
                NAMESPACE="${1#*=}"
                shift
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --project=*)
                PROJECT_NAME="${1#*=}"
                shift
                ;;
            --project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --repo=*)
                REPO_URL="${1#*=}"
                shift
                ;;
            --repo)
                REPO_URL="$2"
                shift 2
                ;;
            --chart-path=*)
                CHART_PATH="${1#*=}"
                shift
                ;;
            --chart-path)
                CHART_PATH="$2"
                shift 2
                ;;
            --ssh-key=*)
                SSH_KEY_PATH="${1#*=}"
                shift
                ;;
            --ssh-key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            *)
                # Unknown option, will be handled by main case statement
                break
                ;;
        esac
    done
}

# Apply defaults if not set
apply_defaults() {
    if [ -z "$NAMESPACE" ]; then
        NAMESPACE="$DEFAULT_NAMESPACE"
    fi
    if [ -z "$APP_NAME" ]; then
        APP_NAME="$DEFAULT_APP_NAME"
    fi
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    fi
    if [ -z "$REPO_URL" ]; then
        REPO_URL="$DEFAULT_REPO_URL"
    fi
    if [ -z "$CHART_PATH" ]; then
        CHART_PATH="$DEFAULT_CHART_PATH"
    fi
    if [ -z "$SSH_KEY_PATH" ]; then
        SSH_KEY_PATH="$DEFAULT_SSH_KEY_PATH"
    fi
}

show_usage() {
    echo "Usage: $0 install [OPTIONS]"
    echo "       $0 uninstall [OPTIONS]"
    echo "       $0 status [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install    - Install Amazon Watcher Backend via ArgoCD"
    echo "  uninstall  - Uninstall Amazon Watcher Backend and clean up all resources (requires --force)"
    echo "  status     - Show current Amazon Watcher Backend deployment status"
    echo ""
    echo "Options:"
    echo "  --app NAME           ArgoCD application name (default: ${DEFAULT_APP_NAME})"
    echo "  --namespace NAME     Target Kubernetes namespace (default: ${DEFAULT_NAMESPACE})"
    echo "  --project NAME       ArgoCD project name (default: ${DEFAULT_PROJECT_NAME})"
    echo "  --repo URL           Git repository URL (default: ${DEFAULT_REPO_URL})"
    echo "  --chart-path PATH    Helm chart path in repository (default: ${DEFAULT_CHART_PATH})"
    echo "  --ssh-key PATH       SSH key path for private repos (default: ${DEFAULT_SSH_KEY_PATH})"
    echo "  --force              Delete and recreate existing resources (apps, projects)"
    echo ""
    echo "Examples:"
    echo "  # Install with defaults"
    echo "  $0 install"
    echo ""
    echo "  # Install with custom app name"
    echo "  $0 install --app staging"
    echo ""
    echo "  # Force recreate existing app"
    echo "  $0 install --app prod --force"
    echo ""
    echo "  # Uninstall (requires --force)"
    echo "  $0 uninstall --force"
}

# Main script
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    install)
        parse_args "$@"
        apply_defaults
        check_prerequisites
        install_amazon_watcher_backend
        ;;
    uninstall)
        parse_args "$@"
        apply_defaults
        check_prerequisites
        uninstall_amazon_watcher_backend
        ;;
    status)
        parse_args "$@"
        apply_defaults
        check_prerequisites
        show_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

