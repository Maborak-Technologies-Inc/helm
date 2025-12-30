#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_NAMESPACE="argocd"
ARGOCD_PORT=8080

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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Please install Helm first."
        exit 1
    fi
    
    # Check argocd CLI
    if ! command -v argocd &> /dev/null; then
        print_error "argocd CLI is not installed. Please install ArgoCD CLI first."
        print_info "Installation: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    print_info "Prerequisites check passed"
}

install_argocd() {
    print_step "Step 1: Installing ArgoCD"
    
    # Create namespace
    print_info "Creating namespace '${ARGOCD_NAMESPACE}'..."
    kubectl create namespace ${ARGOCD_NAMESPACE} 2>/dev/null || print_warn "Namespace '${ARGOCD_NAMESPACE}' already exists"
    
    # Add ArgoCD Helm repo
    print_info "Adding ArgoCD Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || print_warn "Repository may already exist"
    helm repo update
    
    # Install ArgoCD
    print_info "Installing ArgoCD with cluster-scoped mode enabled..."
    if helm list -n ${ARGOCD_NAMESPACE} | grep -q argocd; then
        print_warn "ArgoCD is already installed. Upgrading..."
        helm upgrade argocd argo/argo-cd -n ${ARGOCD_NAMESPACE} \
            --set server.service.type=LoadBalancer \
            --set controller.applicationNamespaces=""
    else
        helm install argocd argo/argo-cd -n ${ARGOCD_NAMESPACE} \
            --set server.service.type=LoadBalancer \
            --set controller.applicationNamespaces=""
    fi
    
    # Wait for ArgoCD to be ready
    print_info "Waiting for ArgoCD server to be ready (this may take a minute)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NAMESPACE} --timeout=120s || {
        print_error "ArgoCD server failed to become ready"
        exit 1
    }
    
    print_info "ArgoCD installed successfully"
}

setup_port_forward() {
    print_step "Step 2: Setting up ArgoCD access"
    
    # Check if port-forward is already running
    if lsof -Pi :${ARGOCD_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warn "Port ${ARGOCD_PORT} is already in use. Killing existing port-forward..."
        pkill -f "port-forward.*argocd-server.*${ARGOCD_PORT}" || true
        sleep 2
    fi
    
    # Start port-forward
    print_info "Starting port-forward on port ${ARGOCD_PORT}..."
    kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} ${ARGOCD_PORT}:443 > /tmp/argocd-portforward.log 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    
    # Verify port-forward is working
    if ! curl -s -k https://localhost:${ARGOCD_PORT} &> /dev/null; then
        print_warn "Port-forward may not be working yet. Waiting a bit more..."
        sleep 5
    fi
    
    print_info "Port-forward established on port ${ARGOCD_PORT}"
}

get_and_display_password() {
    print_step "Step 3: Getting ArgoCD admin password"
    
    # Wait for secret to be available
    print_info "Waiting for ArgoCD admin secret..."
    for i in {1..30}; do
        if kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} &> /dev/null; then
            break
        fi
        sleep 2
    done
    
    # Get password
    ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [ -z "$ARGOCD_PASSWORD" ]; then
        print_error "Could not retrieve ArgoCD admin password"
        print_info "You may need to wait a bit longer for ArgoCD to initialize"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ArgoCD Admin Credentials${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Username: ${BLUE}admin${NC}"
    echo -e "Password: ${BLUE}${ARGOCD_PASSWORD}${NC}"
    echo -e "UI URL:   ${BLUE}https://localhost:${ARGOCD_PORT}${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    print_warn "Save this password securely! You'll need it to access the ArgoCD UI."
    echo ""
    
    # Login to ArgoCD CLI
    print_info "Logging into ArgoCD CLI..."
    argocd login localhost:${ARGOCD_PORT} --insecure --username admin --password "${ARGOCD_PASSWORD}" || {
        print_error "Failed to login to ArgoCD"
        exit 1
    }
    
    print_info "Successfully logged into ArgoCD CLI"
    export ARGOCD_PASSWORD
}


show_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ArgoCD Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "ArgoCD is now installed and ready:"
    echo ""
    echo "  • ArgoCD UI: https://localhost:${ARGOCD_PORT}"
    echo "  • Username: admin"
    echo "  • Password: ${ARGOCD_PASSWORD}"
    echo ""
    echo "Next Steps:"
    echo "  1. Access ArgoCD UI at https://localhost:${ARGOCD_PORT}"
    echo "  2. Create projects and applications as needed"
    echo ""
    echo "Common Commands:"
    echo "  • List projects: argocd proj list"
    echo "  • Create project: argocd proj create <name>"
    echo "  • List apps: argocd app list"
    echo "  • Create app: argocd app create <app-name> ..."
    echo "  • Get app status: argocd app get <app-name>"
    echo "  • Sync app: argocd app sync <app-name>"
    echo ""
    echo "For cluster-scoped resources (like PersistentVolumes):"
    echo "  • Allow in project: argocd proj allow-cluster-resource <project> \"\" PersistentVolume"
    echo "  • Note: Use PascalCase singular form (PersistentVolume, not persistentvolumes)"
    echo ""
    print_warn "Note: Port-forward is running in the background. Keep this terminal open or run it separately."
    echo ""
}

uninstall_argocd() {
    print_info "Uninstalling ArgoCD..."
    
    # Stop port-forward
    print_info "Stopping port-forward..."
    pkill -f "port-forward.*argocd-server" || true
    
    # Delete applications first
    print_info "Deleting ArgoCD applications..."
    argocd app list -o name 2>/dev/null | while read app; do
        if [ -n "$app" ]; then
            print_info "Deleting application: $app"
            argocd app delete "$app" --yes 2>/dev/null || true
        fi
    done
    
    # Uninstall Helm release
    print_info "Uninstalling ArgoCD Helm release..."
    helm uninstall argocd -n ${ARGOCD_NAMESPACE} 2>/dev/null || print_warn "ArgoCD may not be installed"
    
    # Delete namespace
    print_info "Deleting namespace '${ARGOCD_NAMESPACE}'..."
    kubectl delete namespace ${ARGOCD_NAMESPACE} 2>/dev/null || print_warn "Namespace may not exist"
    
    print_info "ArgoCD uninstalled"
}

show_status() {
    print_info "ArgoCD Status:"
    echo ""
    
    # Check if ArgoCD is installed
    if kubectl get namespace ${ARGOCD_NAMESPACE} &> /dev/null; then
        echo "ArgoCD Namespace: ${ARGOCD_NAMESPACE}"
        echo ""
        
        echo "ArgoCD Pods:"
        kubectl get pods -n ${ARGOCD_NAMESPACE}
        echo ""
        
        echo "ArgoCD Services:"
        kubectl get svc -n ${ARGOCD_NAMESPACE}
        echo ""
        
        # Check if logged in
        if argocd account get-user-info &> /dev/null; then
            echo "ArgoCD CLI: Connected"
            echo ""
            echo "Projects:"
            argocd proj list
            echo ""
            echo "Applications:"
            argocd app list
        else
            echo "ArgoCD CLI: Not connected"
            echo "  Run: argocd login localhost:${ARGOCD_PORT} --insecure"
        fi
    else
        print_warn "ArgoCD namespace '${ARGOCD_NAMESPACE}' does not exist"
    fi
}

show_usage() {
    echo "Usage: $0 {install|uninstall|status}"
    echo ""
    echo "Commands:"
    echo "  install    - Install and configure ArgoCD"
    echo "  uninstall  - Uninstall ArgoCD and clean up all resources"
    echo "  status     - Show current ArgoCD status"
    echo ""
    echo "Configuration (edit script to change):"
    echo "  ArgoCD Namespace: ${ARGOCD_NAMESPACE}"
    echo "  ArgoCD Port: ${ARGOCD_PORT}"
}

# Main script
case "${1:-}" in
    install)
        check_prerequisites
        install_argocd
        setup_port_forward
        get_and_display_password
        show_summary
        ;;
    uninstall)
        check_prerequisites
        uninstall_argocd
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

