#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="automated"
APP_NAME="prod"
PROJECT_NAME="zabbix"
REPO_URL="git@github.com:Maborak-Technologies-Inc/helm.git"
CHART_PATH="charts/zabbix"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa_argocd"
ARGOCD_PORT=8080
ZABBIX_UI_PORT=8081

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

install_zabbix() {
    print_info "Starting Zabbix installation..."
    
    # Step 1: Create namespace
    print_info "Creating namespace '${NAMESPACE}'..."
    kubectl create namespace ${NAMESPACE} 2>/dev/null || print_warn "Namespace '${NAMESPACE}' already exists"
    
    # Step 2: Verify ArgoCD project exists
    print_info "Verifying ArgoCD project '${PROJECT_NAME}'..."
    if ! argocd proj get ${PROJECT_NAME} &> /dev/null; then
        print_info "Creating ArgoCD project '${PROJECT_NAME}'..."
        argocd proj create ${PROJECT_NAME} --description "Zabbix project"
        
        # Allow PersistentVolume
        print_info "Allowing PersistentVolume in project..."
        argocd proj allow-cluster-resource ${PROJECT_NAME} "" PersistentVolume
        
        # Add repository to project
        print_info "Adding repository to project..."
        argocd proj add-source ${PROJECT_NAME} ${REPO_URL}
        
        # Add destination namespace
        print_info "Adding destination namespace to project..."
        argocd proj add-destination ${PROJECT_NAME} https://kubernetes.default.svc ${NAMESPACE}
    else
        print_info "Project '${PROJECT_NAME}' already exists"
    fi
    
    # Step 3: Add repository to ArgoCD
    print_info "Adding repository to ArgoCD..."
    if ! argocd repo list | grep -q "${REPO_URL}"; then
        if [ -f "${SSH_KEY_PATH}" ]; then
            argocd repo add ${REPO_URL} --ssh-private-key-path ${SSH_KEY_PATH} || print_warn "Repository may already exist"
        else
            print_error "SSH key not found at ${SSH_KEY_PATH}"
            exit 1
        fi
    else
        print_info "Repository already added"
    fi
    
    # Step 4: Create ArgoCD application
    print_info "Creating ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        print_warn "Application '${APP_NAME}' already exists. Deleting it first..."
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
    fi
    
    # Create application with upsert flag to handle any remaining edge cases
    print_info "Creating ArgoCD application..."
    if ! argocd app create ${APP_NAME} \
        --repo ${REPO_URL} \
        --path ${CHART_PATH} \
        --dest-name in-cluster \
        --dest-namespace ${NAMESPACE} \
        --project ${PROJECT_NAME} \
        --upsert 2>/dev/null; then
        # If upsert doesn't work, try without it (for older ArgoCD versions)
        print_info "Trying without upsert flag..."
        argocd app create ${APP_NAME} \
            --repo ${REPO_URL} \
            --path ${CHART_PATH} \
            --dest-name in-cluster \
            --dest-namespace ${NAMESPACE} \
            --project ${PROJECT_NAME}
    fi
    
    # Step 5: Sync application
    print_info "Syncing application..."
    argocd app sync ${APP_NAME}
    
    # Step 6: Wait for pods to be ready
    print_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=zabbixprod-mariadb -n ${NAMESPACE} --timeout=300s || print_warn "MariaDB pod not ready yet"
    kubectl wait --for=condition=ready pod -l app=zabbixprod-server -n ${NAMESPACE} --timeout=300s || print_warn "Server pod not ready yet"
    kubectl wait --for=condition=ready pod -l app=zabbixprod-ui -n ${NAMESPACE} --timeout=300s || print_warn "UI pod not ready yet"
    
    # Step 7: Setup port-forward for UI
    print_info "Setting up port-forward for Zabbix UI on port ${ZABBIX_UI_PORT}..."
    pkill -f "port-forward.*zabbixprod-ui" 2>/dev/null || true
    kubectl port-forward svc/zabbixprod-ui -n ${NAMESPACE} ${ZABBIX_UI_PORT}:80 > /tmp/zabbix-portforward.log 2>&1 &
    sleep 2
    
    # Verify port-forward
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:${ZABBIX_UI_PORT} | grep -q "200"; then
        print_info "Port-forward is working"
    else
        print_warn "Port-forward may not be working yet"
    fi
    
    # Display status
    print_info "Installation complete!"
    echo ""
    print_info "Zabbix UI is available at: http://localhost:${ZABBIX_UI_PORT}"
    print_info "Default credentials:"
    echo "  Username: Admin"
    echo "  Password: zabbix"
    echo ""
    print_info "To check status: kubectl get pods -n ${NAMESPACE}"
    print_info "To view ArgoCD app: argocd app get ${APP_NAME}"
}

uninstall_zabbix() {
    print_info "Starting Zabbix uninstallation..."
    
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
    pkill -f "port-forward.*zabbixprod-ui" 2>/dev/null || true
    
    # Step 3: Delete PersistentVolumes
    print_info "Deleting PersistentVolumes..."
    kubectl get pv | grep zabbix | awk '{print $1}' | while read pv; do
        print_info "Deleting PV: ${pv}"
        kubectl delete pv ${pv} 2>/dev/null || true
    done
    
    # Step 4: Delete namespace (this will delete all resources)
    print_info "Deleting namespace '${NAMESPACE}'..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${NAMESPACE} --wait=true
        print_info "Waiting for namespace deletion to complete..."
        sleep 5
    else
        print_info "Namespace '${NAMESPACE}' does not exist"
    fi
    
    # Step 5: Verify cleanup
    print_info "Verifying cleanup..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_warn "Namespace still exists (may be in terminating state)"
    else
        print_info "Namespace deleted successfully"
    fi
    
    # Check for any remaining Zabbix resources
    REMAINING_PVS=$(kubectl get pv 2>/dev/null | grep -i zabbix | wc -l)
    if [ "${REMAINING_PVS}" -gt 0 ]; then
        print_warn "Found ${REMAINING_PVS} remaining PersistentVolume(s)"
        kubectl get pv | grep -i zabbix
    else
        print_info "No PersistentVolumes found"
    fi
    
    REMAINING_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -i zabbix | wc -l)
    if [ "${REMAINING_PODS}" -gt 0 ]; then
        print_warn "Found ${REMAINING_PODS} remaining pod(s)"
    else
        print_info "No Zabbix pods found"
    fi
    
    print_info "Uninstallation complete!"
}

show_status() {
    print_info "Zabbix Status:"
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
        echo "Pods:"
        kubectl get pods -n ${NAMESPACE}
        echo ""
        
        echo "Services:"
        kubectl get svc -n ${NAMESPACE}
        echo ""
        
        echo "PersistentVolumes:"
        kubectl get pv | grep zabbix || echo "  No Zabbix PVs found"
        echo ""
        
        echo "PersistentVolumeClaims:"
        kubectl get pvc -n ${NAMESPACE}
    else
        print_warn "Namespace '${NAMESPACE}' does not exist"
    fi
}

show_usage() {
    echo "Usage: $0 {install|uninstall|status}"
    echo ""
    echo "Commands:"
    echo "  install    - Install Zabbix via ArgoCD"
    echo "  uninstall  - Uninstall Zabbix and clean up all resources including PVs"
    echo "  status     - Show current Zabbix deployment status"
    echo ""
    echo "Configuration (edit script to change):"
    echo "  Namespace: ${NAMESPACE}"
    echo "  App Name: ${APP_NAME}"
    echo "  Project: ${PROJECT_NAME}"
    echo "  Repository: ${REPO_URL}"
    echo "  Chart Path: ${CHART_PATH}"
    echo "  SSH Key: ${SSH_KEY_PATH}"
}

# Main script
case "${1:-}" in
    install)
        check_prerequisites
        install_zabbix
        ;;
    uninstall)
        check_prerequisites
        uninstall_zabbix
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

