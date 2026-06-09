#!/bin/bash

set -e

# =============================================================================
# deploy.sh - Unified ArgoCD deployment script for all Helm charts
#
# Consolidates deployment logic for:
#   - amazon-watcher-stack
#   - zabbix
#
# Usage:
#   ./deploy.sh <chart> <command> [OPTIONS]
#
# Examples:
#   ./deploy.sh amazon-watcher install
#   ./deploy.sh zabbix install --version 7.4.6
#   ./deploy.sh amazon-watcher status
#   ./deploy.sh zabbix uninstall --force
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global defaults
DEFAULT_REPO_URL="git@github.com:Maborak-Technologies-Inc/helm.git"
DEFAULT_SSH_KEY_PATH="${HOME}/.ssh/id_rsa_argocd"
ARGOCD_PORT=8080

# Runtime variables
CHART=""
NAMESPACE=""
APP_NAME=""
PROJECT_NAME=""
REPO_URL=""
CHART_PATH=""
SSH_KEY_PATH=""
FORCE=false
ZABBIX_VERSION=""  # Zabbix-specific: version override

# Script directory (for finding templates)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# Output helpers
# =============================================================================

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Per-chart defaults
# =============================================================================

set_chart_defaults() {
    case "$CHART" in
        amazon-watcher)
            DEFAULT_NAMESPACE="automated"
            DEFAULT_APP_NAME="prod"
            DEFAULT_PROJECT_NAME="amazon-watcher"
            DEFAULT_CHART_PATH="charts/amazon-watcher-stack"
            API_PORT=9000
            ;;
        zabbix)
            DEFAULT_NAMESPACE="automated"
            DEFAULT_APP_NAME="prod"
            DEFAULT_PROJECT_NAME="zabbix"
            DEFAULT_CHART_PATH="charts/zabbix"
            ZABBIX_UI_PORT=8081
            ;;
        tiktok-analytics)
            DEFAULT_NAMESPACE="tiktok"
            DEFAULT_APP_NAME="tiktok-prod"
            DEFAULT_PROJECT_NAME="tiktok-analytics"
            DEFAULT_CHART_PATH="charts/tiktok-analytics-stack"
            API_PORT=9020
            ;;
        *)
            print_error "Unknown chart: ${CHART}"
            print_info "Available charts: amazon-watcher, zabbix, tiktok-analytics"
            exit 1
            ;;
    esac
}

# =============================================================================
# Prerequisites
# =============================================================================

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
        print_info "Example: argocd login <ARGOCD_SERVER> --username admin --password <PASSWORD>"
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

# =============================================================================
# Sync helpers
# =============================================================================

wait_for_sync_completion() {
    local app_name=$1
    local timeout=${2:-60}
    local elapsed=0

    print_info "Checking for in-progress operations on '${app_name}'..."

    local app_info=$(argocd app get ${app_name} -o json 2>/dev/null || echo "")

    if [ -z "$app_info" ]; then
        print_warn "Could not get application info, assuming no operation in progress"
        return 0
    fi

    local operation_state=$(echo "$app_info" | grep -o '"operationState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")

    if [ -z "$operation_state" ] || [ "$operation_state" = "null" ]; then
        print_info "No operation in progress"
        return 0
    fi

    if echo "$operation_state" | grep -qi "running"; then
        print_info "Operation in progress (state: ${operation_state}), waiting for completion..."
        while [ $elapsed -lt $timeout ]; do
            sleep 2
            elapsed=$((elapsed + 2))

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

        print_warn "Timeout waiting for operation to complete. Attempting to terminate..."
        argocd app terminate-op ${app_name} 2>/dev/null || true
        sleep 3
    elif echo "$operation_state" | grep -qi "succeeded\|failed"; then
        print_info "Previous operation completed (state: ${operation_state})"
        return 0
    else
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
        local sync_status=$(argocd app get ${app_name} -o json 2>/dev/null | grep -o '"sync":{"status":"[^"]*"' | head -1 | cut -d'"' -f6 || echo "")

        if [ "$sync_status" = "Synced" ]; then
            print_info "Application is synced"
            return 0
        fi

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

    wait_for_sync_completion ${app_name} 60

    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        print_info "Attempting sync (attempt $((retry + 1))/${max_retries})..."

        if argocd app sync ${app_name} > /tmp/argocd-sync.log 2>&1; then
            cat /tmp/argocd-sync.log
            print_info "Sync initiated successfully"
            return 0
        else
            cat /tmp/argocd-sync.log
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
                    if argocd app sync ${app_name} 2>/dev/null; then
                        print_info "Sync initiated after terminating stuck operation"
                        return 0
                    fi
                fi
            else
                print_error "Sync failed with different error"
                return 1
            fi
        fi
    done

    print_error "Failed to sync after ${max_retries} attempts"
    return 1
}

# =============================================================================
# Interactive Confirmation and Dependency Checking
# =============================================================================

confirm_action() {
    local prompt_msg="$1"
    local default_choice="${2:-y}"
    local choice
    
    if [ "$default_choice" = "y" ] || [ "$default_choice" = "Y" ]; then
        prompt_msg="${prompt_msg} [Y/n]: "
    else
        prompt_msg="${prompt_msg} [y/N]: "
    fi
    
    # If stdin is not a TTY (non-interactive), assume default choice
    if [ ! -t 0 ]; then
        print_info "Non-interactive environment, using default choice '$default_choice'"
        if [ "$default_choice" = "y" ] || [ "$default_choice" = "Y" ]; then
            return 0
        else
            return 1
        fi
    fi

    # Read user input
    echo -ne "${YELLOW}${prompt_msg}${NC}"
    read choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    
    if [ -z "$choice" ]; then
        choice=$(echo "$default_choice" | tr '[:upper:]' '[:lower:]')
    fi
    
    if [ "$choice" = "y" ] || [ "$choice" = "yes" ]; then
        return 0
    else
        return 1
    fi
}

ensure_image_pull_secret() {
    local secret_name="apt-docker-server"
    if kubectl get secret ${secret_name} -n ${NAMESPACE} &>/dev/null; then
        print_info "Image pull secret '${secret_name}' already exists in namespace '${NAMESPACE}'"
    else
        print_warn "Image pull secret '${secret_name}' is missing in namespace '${NAMESPACE}'"
        if kubectl get secret ${secret_name} -n automated &>/dev/null; then
            if confirm_action "Do you want to copy the image pull secret '${secret_name}' from the 'automated' namespace?" "y"; then
                print_info "Copying secret '${secret_name}' from 'automated' to '${NAMESPACE}'..."
                kubectl get secret ${secret_name} -n automated -o json | \
                    jq 'del(.metadata.namespace, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.selfLink)' | \
                    kubectl apply -n ${NAMESPACE} -f - || {
                        print_error "Failed to copy secret '${secret_name}'"
                        exit 1
                    }
                print_info "Successfully copied secret '${secret_name}'"
            else
                print_warn "Skipped copying image pull secret. Pods may fail to pull images."
            fi
        else
            print_warn "Could not find image pull secret '${secret_name}' in namespace 'automated' to copy."
        fi
    fi
}

# =============================================================================
# Common install flow
# =============================================================================

create_namespace() {
    if kubectl get namespace ${NAMESPACE} &>/dev/null; then
        print_info "Namespace '${NAMESPACE}' already exists"
    else
        if confirm_action "Kubernetes namespace '${NAMESPACE}' does not exist. Do you want to create it?" "y"; then
            print_info "Creating namespace '${NAMESPACE}'..."
            kubectl create namespace ${NAMESPACE} || {
                print_error "Failed to create namespace '${NAMESPACE}'"
                exit 1
            }
        else
            print_error "Namespace '${NAMESPACE}' is required for installation. Aborting."
            exit 1
        fi
    fi
    
    # Check image pull secret requirements
    if [ "$CHART" = "amazon-watcher" ] || [ "$CHART" = "tiktok-analytics" ]; then
        ensure_image_pull_secret
    fi
}

setup_argocd_project() {
    local project_description="$1"

    print_info "Verifying ArgoCD project '${PROJECT_NAME}'..."
    if argocd proj get ${PROJECT_NAME} &> /dev/null; then
        if [ "$FORCE" = true ]; then
            if confirm_action "Project '${PROJECT_NAME}' already exists. Recreate it (--force enabled)?" "y"; then
                print_warn "Deleting project '${PROJECT_NAME}'..."
                argocd proj delete ${PROJECT_NAME} --yes || {
                    print_error "Failed to delete existing project"
                    exit 1
                }
                print_info "Creating project '${PROJECT_NAME}'..."
                argocd proj create ${PROJECT_NAME} --description "${project_description}" || {
                    print_error "Failed to create project"
                    exit 1
                }
            else
                print_info "Keeping existing project '${PROJECT_NAME}'"
            fi
        else
            print_warn "Project '${PROJECT_NAME}' already exists (skipping creation)"
        fi
    else
        if confirm_action "ArgoCD project '${PROJECT_NAME}' does not exist. Do you want to create it?" "y"; then
            print_info "Creating ArgoCD project '${PROJECT_NAME}'..."
            argocd proj create ${PROJECT_NAME} --description "${project_description}" || {
                print_error "Failed to create project"
                exit 1
            }
        else
            print_error "ArgoCD project '${PROJECT_NAME}' is required for installation. Aborting."
            exit 1
        fi
    fi

    # Add repository to project
    print_info "Adding repository to project..."
    argocd proj add-source ${PROJECT_NAME} ${REPO_URL} 2>/dev/null || print_warn "Repository may already be added to project"

    # Add destination namespace
    print_info "Adding destination namespace to project..."
    argocd proj add-destination ${PROJECT_NAME} https://kubernetes.default.svc ${NAMESPACE} 2>/dev/null || print_warn "Destination may already be added"
}

add_repo_to_argocd() {
    print_info "Verifying ArgoCD repository registry..."
    if ! argocd repo list | grep -q "${REPO_URL}"; then
        if confirm_action "Git repository '${REPO_URL}' is not registered in ArgoCD. Do you want to register it?" "y"; then
            if [ -f "${SSH_KEY_PATH}" ]; then
                argocd repo add ${REPO_URL} --ssh-private-key-path ${SSH_KEY_PATH} || {
                    print_error "Failed to add repository to ArgoCD"
                    exit 1
                }
            else
                print_error "SSH key not found at ${SSH_KEY_PATH}"
                print_info "Please provide SSH key path with --ssh-key option"
                exit 1
            fi
        else
            print_error "ArgoCD repository is required for deployment. Aborting."
            exit 1
        fi
    else
        print_info "Repository already registered in ArgoCD"
    fi
}

delete_existing_app() {
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        if [ "$FORCE" = true ]; then
            if confirm_action "Application '${APP_NAME}' already exists. Force delete and recreate it?" "y"; then
                print_warn "Deleting application '${APP_NAME}'..."
                argocd app delete ${APP_NAME} --yes 2>/dev/null || kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
                print_info "Waiting for application deletion to complete..."
                sleep 3

                TIMEOUT=30
                ELAPSED=0
                while (argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null) && [ $ELAPSED -lt $TIMEOUT ]; do
                    print_info "Waiting for application to be fully deleted... (${ELAPSED}s/${TIMEOUT}s)"
                    sleep 2
                    ELAPSED=$((ELAPSED + 2))
                done
                if [ $ELAPSED -ge $TIMEOUT ]; then
                    print_warn "Application deletion taking longer than expected. Removing finalizers..."
                    kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    sleep 2
                    kubectl delete application ${APP_NAME} -n argocd --force --grace-period=0 2>/dev/null || true
                    sleep 3
                fi
            else
                print_info "Proceeding with existing application..."
            fi
        else
            print_error "Application '${APP_NAME}' already exists!"
            print_info "Use a different name or add --force to delete and recreate it."
            print_info "Example: $0 ${CHART} install --app ${APP_NAME}-new --force"
            exit 1
        fi
    fi
}

# =============================================================================
# Chart-specific: tiktok-analytics install / uninstall / status
# =============================================================================

install_tiktok_analytics() {
    print_info "Starting TikTok Analytics Stack installation..."

    create_namespace
    setup_argocd_project "TikTok Analytics project"
    add_repo_to_argocd
    delete_existing_app

    # Create application via ArgoCD CLI
    print_info "Creating ArgoCD application with auto-sync enabled..."

    BASE_ARGS=(
        --repo "${REPO_URL}"
        --path "${CHART_PATH}"
        --dest-name in-cluster
        --dest-namespace "${NAMESPACE}"
        --project "${PROJECT_NAME}"
        --sync-policy automated
        --self-heal
        --auto-prune
        --helm-set "global.releaseName=${APP_NAME}"
    )

    if ! argocd app create "${APP_NAME}" \
        "${BASE_ARGS[@]}" \
        --upsert 2>/dev/null; then
        print_info "Trying without upsert flag..."
        argocd app create "${APP_NAME}" \
            "${BASE_ARGS[@]}"
    fi

    # Configure ignoreDifferences for Rollout replicas (HPA manages these)
    print_info "Setting ignoreDifferences for Rollout replicas..."
    argocd app patch "${APP_NAME}" --type merge --patch \
        '{"spec":{"ignoreDifferences":[{"group":"argoproj.io","kind":"Rollout","jsonPointers":["/spec/replicas"]}]}}' 2>/dev/null || \
        print_warn "Could not set ignoreDifferences (may require manual configuration)"

    print_info "✅ ArgoCD Application created"

    # Wait for auto-sync
    print_info "Waiting for auto-sync to complete..."
    wait_for_app_synced ${APP_NAME} 120 || {
        print_warn "Auto-sync may still be in progress. Continuing to wait for pods..."
    }

    # Wait for pods
    print_info "Waiting for pods to be ready..."
    HELM_RELEASE="tiktok-analytics-stack${APP_NAME}"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE} -n ${NAMESPACE} --timeout=300s || print_warn "Pod not ready yet"

    # Display status
    print_info "Installation complete!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  TikTok Analytics Stack Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access TikTok Analytics Backend API:${NC}"
    echo ""
    echo -e "${GREEN}Option 1: Using kubectl proxy (Recommended)${NC}"
    echo "  1. Start kubectl proxy in a separate terminal:"
    echo -e "     ${GREEN}kubectl proxy${NC}"
    echo ""
    echo "  2. Access API via proxy:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/${NAMESPACE}/services/${HELM_RELEASE}:${API_PORT}/proxy/${NC}"
    echo ""
    echo -e "${GREEN}Option 2: Using port-forward (Direct access)${NC}"
    echo "  1. Run port-forward in a separate terminal:"
    echo -e "     ${GREEN}kubectl port-forward svc/${HELM_RELEASE} -n ${NAMESPACE} ${API_PORT}:${API_PORT}${NC}"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • Check status: ${GREEN}kubectl get pods -n ${NAMESPACE}${NC}"
    echo -e "  • View ArgoCD app: ${GREEN}argocd app get ${APP_NAME}${NC}"
    echo ""
}

uninstall_tiktok_analytics() {
    if [ "$FORCE" != true ]; then
        print_error "Uninstall requires --force flag for safety"
        print_info "Usage: $0 tiktok-analytics uninstall --force"
        print_warn "This will delete the ArgoCD application and all TikTok Analytics resources!"
        exit 1
    fi

    print_warn "Starting TikTok Analytics Stack uninstallation (--force enabled)..."

    # Delete ArgoCD application
    print_info "Deleting ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        argocd app delete ${APP_NAME} --yes 2>/dev/null || true
        sleep 2

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
            sleep 2
        fi

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            print_warn "Application deletion stuck, removing finalizers..."
            kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            sleep 2
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
        fi

        sleep 2
    else
        print_info "Application '${APP_NAME}' does not exist"
    fi

    # Delete namespace
    print_info "Deleting namespace '${NAMESPACE}'..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${NAMESPACE} --wait=true
        print_info "Waiting for namespace deletion to complete..."
        sleep 5
    else
        print_info "Namespace '${NAMESPACE}' does not exist"
    fi

    print_info "Uninstallation complete!"
}

status_tiktok_analytics() {
    print_info "TikTok Analytics Stack Status:"
    echo ""

    if argocd app get ${APP_NAME} &> /dev/null; then
        echo "ArgoCD Application:"
        argocd app get ${APP_NAME} | head -10
        echo ""
    else
        print_warn "Application '${APP_NAME}' does not exist"
    fi

    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        echo "Pods:"
        kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${APP_NAME}
        echo ""

        echo "Services:"
        kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/instance=${APP_NAME}
        echo ""
    else
        print_warn "Namespace '${NAMESPACE}' does not exist"
    fi
}

# =============================================================================
# Chart-specific: amazon-watcher install
# =============================================================================

install_amazon_watcher() {
    print_info "Starting Amazon Watcher Stack installation..."

    create_namespace
    setup_argocd_project "Amazon Watcher Backend project"
    add_repo_to_argocd
    delete_existing_app

    # Create application via ArgoCD CLI
    print_info "Creating ArgoCD application with auto-sync enabled..."

    BASE_ARGS=(
        --repo "${REPO_URL}"
        --path "${CHART_PATH}"
        --dest-name in-cluster
        --dest-namespace "${NAMESPACE}"
        --project "${PROJECT_NAME}"
        --sync-policy automated
        --self-heal
        --auto-prune
        --helm-set "global.releaseName=${APP_NAME}"
    )

    if ! argocd app create "${APP_NAME}" \
        "${BASE_ARGS[@]}" \
        --upsert 2>/dev/null; then
        print_info "Trying without upsert flag..."
        argocd app create "${APP_NAME}" \
            "${BASE_ARGS[@]}"
    fi

    # Configure ignoreDifferences for Rollout replicas (HPA manages these)
    print_info "Setting ignoreDifferences for Rollout replicas..."
    argocd app patch "${APP_NAME}" --type merge --patch \
        '{"spec":{"ignoreDifferences":[{"group":"argoproj.io","kind":"Rollout","jsonPointers":["/spec/replicas"]}]}}' 2>/dev/null || \
        print_warn "Could not set ignoreDifferences (may require manual configuration)"

    print_info "✅ ArgoCD Application created"

    # Wait for auto-sync
    print_info "Waiting for auto-sync to complete..."
    wait_for_app_synced ${APP_NAME} 120 || {
        print_warn "Auto-sync may still be in progress. Continuing to wait for pods..."
    }

    # Wait for pods
    print_info "Waiting for pods to be ready..."
    HELM_RELEASE="amazon-watcher-stack${APP_NAME}"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE} -n ${NAMESPACE} --timeout=300s || print_warn "Pod not ready yet"

    # Display status
    print_info "Installation complete!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Amazon Watcher Stack Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access Amazon Watcher Backend API:${NC}"
    echo ""
    echo -e "${GREEN}Option 1: Using kubectl proxy (Recommended)${NC}"
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

# =============================================================================
# Chart-specific: zabbix install
# =============================================================================

install_zabbix() {
    print_info "Starting Zabbix installation..."

    create_namespace
    setup_argocd_project "Zabbix project"

    # Zabbix-specific: Allow PersistentVolume cluster resource
    print_info "Allowing PersistentVolume in project..."
    argocd proj allow-cluster-resource ${PROJECT_NAME} "" PersistentVolume 2>/dev/null || print_warn "PersistentVolume may already be allowed"

    add_repo_to_argocd
    delete_existing_app

    # Create application via ArgoCD CLI (no ignoreDifferences needed)
    print_info "Creating ArgoCD application with auto-sync enabled..."

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

    # Add Helm set arguments if version is specified
    if [ -n "$ZABBIX_VERSION" ]; then
        print_info "Setting Zabbix version to ${ZABBIX_VERSION} via Helm values..."
        BASE_ARGS+=(
            --helm-set "images.zabbixServer.tag=${ZABBIX_VERSION}"
            --helm-set "images.zabbixUI.tag=${ZABBIX_VERSION}"
            --helm-set "images.mariadb.tag=${ZABBIX_VERSION}"
        )
    fi

    if ! argocd app create "${APP_NAME}" \
        "${BASE_ARGS[@]}" \
        --upsert 2>/dev/null; then
        print_info "Trying without upsert flag..."
        argocd app create "${APP_NAME}" \
            "${BASE_ARGS[@]}"
    fi

    # Wait for auto-sync
    print_info "Waiting for auto-sync to complete..."
    wait_for_app_synced ${APP_NAME} 120 || {
        print_warn "Auto-sync may still be in progress. Continuing to wait for pods..."
    }

    # Wait for pods
    print_info "Waiting for pods to be ready..."
    HELM_RELEASE="zabbix${APP_NAME}"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE}-mariadb -n ${NAMESPACE} --timeout=300s || print_warn "MariaDB pod not ready yet"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE}-server -n ${NAMESPACE} --timeout=300s || print_warn "Server pod not ready yet"
    kubectl wait --for=condition=ready pod -l app=${HELM_RELEASE}-ui -n ${NAMESPACE} --timeout=300s || print_warn "UI pod not ready yet"

    # Display status
    print_info "Installation complete!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Zabbix Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access Zabbix UI:${NC}"
    echo ""
    echo -e "${GREEN}Option 1: Using kubectl proxy (Recommended)${NC}"
    echo "  1. Start kubectl proxy in a separate terminal:"
    echo -e "     ${GREEN}kubectl proxy${NC}"
    echo ""
    echo "  2. Access Zabbix UI via proxy:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/${NAMESPACE}/services/${HELM_RELEASE}-ui:80/proxy/${NC}"
    echo ""
    echo "  3. Access ArgoCD UI via the same proxy:"
    echo -e "     ${GREEN}http://localhost:8001/api/v1/namespaces/argocd/services/argocd-server:443/proxy/${NC}"
    echo ""
    echo -e "${GREEN}Option 2: Using port-forward (Direct access)${NC}"
    echo "  1. Run port-forward in a separate terminal:"
    echo -e "     ${GREEN}kubectl port-forward svc/${HELM_RELEASE}-ui -n ${NAMESPACE} ${ZABBIX_UI_PORT}:80${NC}"
    echo ""
    echo "  2. Open your browser and navigate to:"
    echo -e "     ${GREEN}http://localhost:${ZABBIX_UI_PORT}${NC}"
    echo ""
    echo "  3. Login with default credentials:"
    echo -e "     Username: ${GREEN}Admin${NC}"
    echo -e "     Password: ${GREEN}zabbix${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} Keep the proxy or port-forward command running in a separate terminal."
    echo "      Press Ctrl+C in that terminal to stop it."
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • Check status: ${GREEN}kubectl get pods -n ${NAMESPACE}${NC}"
    echo -e "  • View ArgoCD app: ${GREEN}argocd app get ${APP_NAME}${NC}"
    echo -e "  • Sync app: ${GREEN}argocd app sync ${APP_NAME}${NC}"
    echo ""
}

# =============================================================================
# Chart-specific: amazon-watcher uninstall
# =============================================================================

uninstall_amazon_watcher() {
    if [ "$FORCE" != true ]; then
        print_error "Uninstall requires --force flag for safety"
        print_info "Usage: $0 amazon-watcher uninstall --force"
        print_warn "This will delete the ArgoCD application and all Amazon Watcher resources!"
        exit 1
    fi

    print_warn "Starting Amazon Watcher Stack uninstallation (--force enabled)..."

    # Delete ArgoCD application
    print_info "Deleting ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        argocd app delete ${APP_NAME} --yes 2>/dev/null || true
        sleep 2

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
            sleep 2
        fi

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            print_warn "Application deletion stuck, removing finalizers..."
            kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            sleep 2
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
        fi

        sleep 2
    else
        print_info "Application '${APP_NAME}' does not exist"
    fi

    # Delete namespace
    print_info "Deleting namespace '${NAMESPACE}'..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${NAMESPACE} --wait=true
        print_info "Waiting for namespace deletion to complete..."
        sleep 5
    else
        print_info "Namespace '${NAMESPACE}' does not exist"
    fi

    # Verify cleanup
    print_info "Verifying cleanup..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_warn "Namespace still exists (may be in terminating state)"
    else
        print_info "Namespace deleted successfully"
    fi

    REMAINING_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -i "${APP_NAME}" | wc -l)
    if [ "${REMAINING_PODS}" -gt 0 ]; then
        print_warn "Found ${REMAINING_PODS} remaining pod(s)"
    else
        print_info "No Amazon Watcher pods found"
    fi

    print_info "Uninstallation complete!"
}

# =============================================================================
# Chart-specific: zabbix uninstall
# =============================================================================

uninstall_zabbix() {
    if [ "$FORCE" != true ]; then
        print_error "Uninstall requires --force flag for safety"
        print_info "Usage: $0 zabbix uninstall --force"
        print_warn "This will delete the ArgoCD application, all Zabbix resources, and PersistentVolumes!"
        exit 1
    fi

    print_warn "Starting Zabbix uninstallation (--force enabled)..."

    # Delete ArgoCD application
    print_info "Deleting ArgoCD application '${APP_NAME}'..."
    if argocd app get ${APP_NAME} &> /dev/null || kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
        argocd app delete ${APP_NAME} --yes 2>/dev/null || true
        sleep 2

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
            sleep 2
        fi

        if kubectl get application ${APP_NAME} -n argocd &> /dev/null; then
            print_warn "Application deletion stuck, removing finalizers..."
            kubectl patch application ${APP_NAME} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            sleep 2
            kubectl delete application ${APP_NAME} -n argocd 2>/dev/null || true
        fi

        sleep 2
    else
        print_info "Application '${APP_NAME}' does not exist"
    fi

    # Stop port-forward
    print_info "Stopping port-forward..."
    HELM_RELEASE="zabbix${APP_NAME}"
    pkill -f "port-forward.*${HELM_RELEASE}-ui" 2>/dev/null || true

    # Delete PersistentVolumes
    print_info "Deleting PersistentVolumes..."
    kubectl get pv | grep zabbix | awk '{print $1}' | while read pv; do
        print_info "Deleting PV: ${pv}"
        kubectl delete pv ${pv} 2>/dev/null || true
    done

    # Delete namespace
    print_info "Deleting namespace '${NAMESPACE}'..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        kubectl delete namespace ${NAMESPACE} --wait=true
        print_info "Waiting for namespace deletion to complete..."
        sleep 5
    else
        print_info "Namespace '${NAMESPACE}' does not exist"
    fi

    # Verify cleanup
    print_info "Verifying cleanup..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_warn "Namespace still exists (may be in terminating state)"
    else
        print_info "Namespace deleted successfully"
    fi

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

# =============================================================================
# Chart-specific: amazon-watcher status
# =============================================================================

status_amazon_watcher() {
    print_info "Amazon Watcher Stack Status:"
    echo ""

    if argocd app get ${APP_NAME} &> /dev/null; then
        echo "ArgoCD Application:"
        argocd app get ${APP_NAME} | head -10
        echo ""
    else
        print_warn "Application '${APP_NAME}' does not exist"
    fi

    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        echo "Pods:"
        kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${APP_NAME}
        echo ""

        echo "Services:"
        kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/instance=${APP_NAME}
        echo ""

        echo "PersistentVolumeClaims:"
        kubectl get pvc -n ${NAMESPACE} -l app.kubernetes.io/instance=${APP_NAME} 2>/dev/null || echo "  No PVCs found"
    else
        print_warn "Namespace '${NAMESPACE}' does not exist"
    fi
}

# =============================================================================
# Chart-specific: zabbix status
# =============================================================================

status_zabbix() {
    print_info "Zabbix Status:"
    echo ""

    if argocd app get ${APP_NAME} &> /dev/null; then
        echo "ArgoCD Application:"
        argocd app get ${APP_NAME} | head -10
        echo ""
    else
        print_warn "Application '${APP_NAME}' does not exist"
    fi

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

# =============================================================================
# Argument parsing
# =============================================================================

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
            --version=*)
                ZABBIX_VERSION="${1#*=}"
                shift
                ;;
            --version)
                ZABBIX_VERSION="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
}

apply_defaults() {
    [ -z "$NAMESPACE" ] && NAMESPACE="$DEFAULT_NAMESPACE"
    [ -z "$APP_NAME" ] && APP_NAME="$DEFAULT_APP_NAME"
    [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    [ -z "$REPO_URL" ] && REPO_URL="$DEFAULT_REPO_URL"
    [ -z "$CHART_PATH" ] && CHART_PATH="$DEFAULT_CHART_PATH"
    [ -z "$SSH_KEY_PATH" ] && SSH_KEY_PATH="$DEFAULT_SSH_KEY_PATH"
}

# =============================================================================
# Usage
# =============================================================================

show_usage() {
    echo "Usage: $0 <chart> <command> [OPTIONS]"
    echo ""
    echo "Charts:"
    echo "  amazon-watcher   Amazon Watcher Stack (backend, UI, screenshot, database)"
    echo "  zabbix           Zabbix monitoring stack (server, UI, MariaDB)"
    echo "  tiktok-analytics TikTok Analytics Stack (backend, UI, database, redis, worker)"
    echo ""
    echo "Commands:"
    echo "  install          Install the chart via ArgoCD"
    echo "  uninstall        Uninstall the chart and clean up all resources (requires --force)"
    echo "  status           Show current deployment status"
    echo ""
    echo "Options:"
    echo "  --app NAME           ArgoCD application name (default: prod)"
    echo "  --namespace NAME     Target Kubernetes namespace (default: automated)"
    echo "  --project NAME       ArgoCD project name (default: zabbix)"
    echo "  --repo URL           Git repository URL"
    echo "  --chart-path PATH    Helm chart path in repository"
    echo "  --ssh-key PATH       SSH key path for private repos"
    echo "  --version VERSION    Zabbix version to deploy (zabbix chart only)"
    echo "  --force              Delete and recreate existing resources"
    echo ""
    echo "Examples:"
    echo "  # Install Amazon Watcher with defaults"
    echo "  $0 amazon-watcher install"
    echo ""
    echo "  # Install Zabbix with a specific version"
    echo "  $0 zabbix install --version 7.4.6"
    echo ""
    echo "  # Install TikTok Analytics with defaults"
    echo "  $0 tiktok-analytics install"
    echo ""
    echo "  # Force recreate Amazon Watcher"
    echo "  $0 amazon-watcher install --app prod --force"
    echo ""
    echo "  # Check Zabbix status"
    echo "  $0 zabbix status"
    echo ""
    echo "  # Uninstall Amazon Watcher (requires --force)"
    echo "  $0 amazon-watcher uninstall --force"
}

# =============================================================================
# Main
# =============================================================================

CHART="${1:-}"
COMMAND="${2:-}"
shift 2 || true

if [ -z "$CHART" ] || [ -z "$COMMAND" ]; then
    show_usage
    exit 1
fi

set_chart_defaults
parse_args "$@"
apply_defaults

case "$COMMAND" in
    install)
        check_prerequisites
        case "$CHART" in
            amazon-watcher)   install_amazon_watcher ;;
            zabbix)           install_zabbix ;;
            tiktok-analytics) install_tiktok_analytics ;;
        esac
        ;;
    uninstall)
        check_prerequisites
        case "$CHART" in
            amazon-watcher)   uninstall_amazon_watcher ;;
            zabbix)           uninstall_zabbix ;;
            tiktok-analytics) uninstall_tiktok_analytics ;;
        esac
        ;;
    status)
        check_prerequisites
        case "$CHART" in
            amazon-watcher)   status_amazon_watcher ;;
            zabbix)           status_zabbix ;;
            tiktok-analytics) status_tiktok_analytics ;;
        esac
        ;;
    *)
        print_error "Unknown command: ${COMMAND}"
        show_usage
        exit 1
        ;;
esac

