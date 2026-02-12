#!/bin/bash
# Kubernetes Bootstrap Script
# Installs and configures all infrastructure components for the Amazon Watcher Stack.

# Removed set -e to handle errors manually for Skip/Retry/Abort logic.

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# Helper to read password with asterisk masking
read_password() {
    local prompt="$1"
    local password=""
    local char=""

    echo -n "$prompt" >&2
    while IFS= read -r -s -n1 char; do
        if [[ $char == $'\0' || $char == $'\n' ]]; then
            break
        fi
        if [[ $char == $'\177' || $char == $'\b' ]]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                echo -ne "\b \b" >&2
            fi
        else
            password+="$char"
            echo -n "*" >&2
        fi
    done
    echo "" >&2
    echo "$password"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install it first."
        exit 1
    fi
    log_success "Prerequisites check passed."
}

# Internal helper to retry a command silently
run_with_retry_internal() {
    local cmd="$1"
    local retries=${2:-3}
    local delay=${3:-5}
    local count=0

    while [ $count -lt $retries ]; do
        if eval "$cmd"; then
            return 0
        fi
        count=$((count + 1))
        [ $count -lt $retries ] && log_warn "Command failed. Retrying ($count/$retries) in $delay seconds..."
        [ $count -lt $retries ] && sleep $delay
    done
    return 1
}

# Main command runner with interactive error handling
run_command() {
    local cmd="$1"
    local desc="$2"
    local namespace="$3"
    local selector="$4"

    while true; do
        if run_with_retry_internal "$cmd"; then
            return 0
        fi

        log_error "Failed: $desc"
        [ -n "$namespace" ] && [ -n "$selector" ] && show_troubleshooting "$namespace" "$selector"
        
        echo "Select an action:"
        echo "  [r] Retry this task"
        echo "  [s] Skip this task and continue"
        echo "  [a] Abort entire process"
        read -p "Action [r/s/a]: " choice
        case "$choice" in
            [sS]*) return 1 ;;
            [aA]*) exit 0 ;;
            *) continue ;;
        esac
    done
}

# Check if a resource exists
is_installed() {
    local namespace=$1
    local type=$2
    local name=$3
    
    if kubectl get "$type" "$name" -n "$namespace" &> /dev/null; then
        return 0 # True, exists
    else
        return 1 # False, does not exist
    fi
}

# Show troubleshooting commands
show_troubleshooting() {
    local namespace=$1
    local selector=$2
    
    echo ""
    echo -e "${YELLOW}--- Troubleshooting Suggestions ---${NC}"
    echo "1. Check pod status:"
    echo "   kubectl get pods -n $namespace -l $selector"
    echo "2. View pod logs (pick a pod name from above):"
    echo "   kubectl logs -n $namespace <pod-name>"
    echo "3. Describe pod for events:"
    echo "   kubectl describe pod -n $namespace <pod-name>"
    echo "4. Check events in namespace:"
    echo "   kubectl get events -n $namespace --sort-by='.lastTimestamp'"
    echo ""
}

# Wait for pod with timeout and interactive error handling
wait_for_pod() {
    local namespace=$1
    local selector=$2
    local timeout=${3:-120}
    
    log_info "Waiting for pod ($selector) in namespace $namespace to be ready..."
    
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Get total and ready counts
        local status_info=$(kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{" "}{.status.phase}{" "}{.status.containerStatuses[*].state.waiting.reason}{"\n"}{end}' 2>/dev/null)
        local total=$(echo "$status_info" | grep -v "^$" | wc -l)
        local ready=$(echo "$status_info" | grep "true" | wc -l)
        
        if [ "$total" -gt 0 ] && [ "$ready" -eq "$total" ]; then
            echo -e "\n${GREEN}[SUCCESS]${NC} All $total pods ($selector) are ready."
            return 0
        fi
        
        # Check for error states
        local errors=$(echo "$status_info" | grep -E "CrashLoopBackOff|Error|ImagePullBackOff|ErrImagePull" | wc -l)
        if [ "$errors" -gt 0 ]; then
            echo -ne "\r${RED}[ERROR]${NC} $errors pod(s) are in error state. Checking...          "
        else
            echo -ne "\r  Progress: $ready/$total pods ready (${elapsed}s / ${timeout}s)...\r"
        fi
        
        if [ "$elapsed" -ge "$timeout" ]; then
            echo ""
            log_error "Timeout: Pods with selector '$selector' in namespace '$namespace' are not ready after ${timeout}s."
            show_troubleshooting "$namespace" "$selector"
            
            echo "Select an action:"
            echo "  [r] Retry waiting (resets timeout)"
            echo "  [s] Skip this check and continue"
            echo "  [i] Inspect pods now (kubectl get pods)"
            echo "  [a] Abort entire process"
            read -p "Action [r/s/i/a]: " choice
            case "$choice" in
                [sS]*) return 1 ;;
                [aA]*) exit 0 ;;
                [iI]*) 
                    kubectl get pods -n "$namespace" -l "$selector"
                    read -p "Press Enter to continue waiting..."
                    start_time=$(date +%s)
                    ;;
                *) start_time=$(date +%s); continue ;;
            esac
        fi
        
        sleep 3
    done
}

# Ask user what to do if component is already installed
ask_action_if_installed() {
    local component=$1
    local namespace=$2
    local check_cmd=$3 # Command to check existence
    local extra_info_cmd=$4 # Optional: Command for extra status info
    
    if eval "$check_cmd"; then
        echo ""
        log_warn "$component appears to be already installed."
        while true; do
            echo "Select an action for $component:"
            echo "  [s] Skip current installation (default)"
            echo "  [r] Reinstall (Delete existing & Install fresh)"
            echo "  [c] Check current status"
            echo "  [a] Abort entire process"
            read -p "Action [s/r/c/a]: " action
            action=${action:-s}
            
            case "$action" in
                [rR]*)
                    return 2 # Reinstall
                    ;;
                [cC]*)
                    log_info "Checking status of $component..."
                    kubectl get pods,svc,deploy,ds,sc,pvc -n "$namespace" --ignore-not-found | cat
                    if [ -n "$extra_info_cmd" ]; then
                        echo ""
                        log_info "Custom Resources:"
                        eval "$extra_info_cmd"
                    fi
                    echo ""
                    ;;
                [aA]*)
                    log_warn "Aborting entire process..."
                    exit 0
                    ;;
                *)
                    return 1 # Skip
                    ;;
            esac
        done
    fi
    return 0 # Install fresh
}

# --- Component Installation Functions ---

install_metallb() {
    # Check if installed
    ask_action_if_installed "MetalLB" "metallb-system" "kubectl get deployment controller -n metallb-system &>/dev/null" "kubectl get ipaddresspool,l2advertisement -n metallb-system"
    res=$?
    
    if [ $res -eq 1 ]; then
        log_info "Skipping MetalLB (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
         # Reinstall selected, clean up first
         log_info "Cleaning up previous installation (including CRDs)..."
         kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml --ignore-not-found --wait=true
         kubectl delete namespace metallb-system --ignore-not-found --wait=true
         # Extra cleanup for lingering CRDs if any
         kubectl delete crd bgppeers.metallb.io addresspools.metallb.io bfdprofiles.metallb.io bgpadvertisements.metallb.io communities.metallb.io ipaddresspools.metallb.io l2advertisements.metallb.io 2>/dev/null || true
    fi

    log_info "Installing MetalLB..."
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Proactively create memberlist secret if it doesn't exist
    if ! kubectl get secret memberlist -n metallb-system &>/dev/null; then
        log_info "Creating memberlist secret..."
        kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
    fi

    run_command "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml" "MetalLB Manifests" "metallb-system" "app=metallb" || return 0
    
    # Wait for controller first, then speakers
    wait_for_pod "metallb-system" "component=controller" 60 || return 0
    wait_for_pod "metallb-system" "component=speaker" 120 || return 0
    
    log_info "Configuring MetalLB IP Address Pool..."
    read -p "Enter MetalLB IP Range (default: 10.10.10.40/32): " ip_range
    ip_range=${ip_range:-"10.10.10.40/32"}

    # Generate and apply configuration on the fly
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $ip_range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    log_success "MetalLB setup complete."
}

install_nginx_ingress() {
    ask_action_if_installed "NGINX Ingress" "ingress-nginx" "kubectl get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null" "kubectl get ingress -A"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping NGINX Ingress (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
         kubectl delete namespace ingress-nginx --ignore-not-found --wait=true
    fi

    log_info "Installing NGINX Ingress Controller..."
    run_command "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml" "NGINX Ingress Installation" "ingress-nginx" "app.kubernetes.io/component=controller" || return 0
    
    log_info "Patching NGINX Ingress Service for MetalLB compatibility..."
    sleep 5
    run_command "kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{\"spec\":{\"externalTrafficPolicy\":\"Cluster\"}}'" "NGINX Service Patch" || return 0
    
    wait_for_pod "ingress-nginx" "app.kubernetes.io/component=controller" || return 0
    log_success "NGINX Ingress Controller setup complete."
}

install_argo_rollouts() {
    ask_action_if_installed "Argo Rollouts" "argo-rollouts" "kubectl get deployment argo-rollouts -n argo-rollouts &>/dev/null" "kubectl get rollouts -A 2>/dev/null"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping Argo Rollouts (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
         kubectl delete namespace argo-rollouts --ignore-not-found --wait=true
    fi

    log_info "Installing Argo Rollouts..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    run_command "kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml" "Argo Rollouts Installation" "argo-rollouts" "app.kubernetes.io/name=argo-rollouts" || return 0
    
    wait_for_pod "argo-rollouts" "app.kubernetes.io/name=argo-rollouts" || return 0
    log_success "Argo Rollouts setup complete."
}

install_metrics_server() {
    # Check if installed - but be more thorough (check for both deployment AND APIService)
    local check_cmd="kubectl get deployment metrics-server -n kube-system &>/dev/null && kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null"
    ask_action_if_installed "Metrics Server" "kube-system" "$check_cmd"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping Metrics Server (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
         log_info "Removing old Metrics Server components..."
         kubectl delete deployment metrics-server -n kube-system --ignore-not-found
         kubectl delete service metrics-server -n kube-system --ignore-not-found
         kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found
         kubectl delete clusterrole system:metrics-server metrics-server-reporter --ignore-not-found
         kubectl delete clusterrolebinding system:metrics-server metrics-server:system:auth-reporter --ignore-not-found
         kubectl delete clusterrolebinding metrics-server:system:auth-delegator --ignore-not-found
         kubectl delete rolebinding metrics-server-auth-reader -n kube-system --ignore-not-found
    fi

    log_info "Installing Metrics Server..."
    # Apply official manifests
    run_command "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml" "Metrics Server Installation" "kube-system" "k8s-app=metrics-server" || return 0
    
    # Always apply insecure TLS patch for local/custom clusters to ensure it works
    # We'll ask if they want to skip it, but default to YES since it's most common for this setup
    read -p "Apply insecure TLS patch (highly recommended for local/proxmox clusters)? (Y/n): " apply_patch
    apply_patch=${apply_patch:-y}
    if [[ "$apply_patch" =~ ^[Yy]$ ]]; then
        log_info "Patching Metrics Server (insecure TLS & address types)..."
        # We also add InternalIP preference to help with node connectivity issues like the one seen on node3
        run_command "kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kubelet-insecure-tls\"}, {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname\"}]'" "Metrics Server Patch" || return 0
    fi

    wait_for_pod "kube-system" "k8s-app=metrics-server" || return 0
    
    # Final verification of APIService
    log_info "Verifying Metrics APIService..."
    if kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null; then
        log_success "Metrics Server setup complete and APIService registered."
    else
        log_warn "Metrics Server pod is ready, but APIService 'v1beta1.metrics.k8s.io' is not yet registered. It may take a minute."
    fi
}

install_local_path_provisioner() {
    ask_action_if_installed "Local Path Provisioner" "local-path-storage" "kubectl get deployment local-path-provisioner -n local-path-storage &>/dev/null"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping Local Path Provisioner (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
        kubectl delete namespace local-path-storage --ignore-not-found --wait=true
    fi

    log_info "Installing Local Path Provisioner..."
    run_command "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml" "Local Path Provisioner Installation" "local-path-storage" "app=local-path-provisioner" || return 0
    
    log_info "Setting local-path as default StorageClass..."
    run_command "kubectl patch storageclass local-path -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'" "StorageClass Default Patch" || return 0
    
    wait_for_pod "local-path-storage" "app=local-path-provisioner" || return 0
    log_success "Local Path Provisioner setup complete."
}

install_argocd() {
    ask_action_if_installed "ArgoCD" "argocd" "kubectl get deployment argocd-server -n argocd &>/dev/null" "kubectl get applications -n argocd 2>/dev/null"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping ArgoCD (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
        # For HELM re-installs, uninstall first
        helm uninstall argocd -n argocd 2>/dev/null || true
        kubectl delete namespace argocd --ignore-not-found --wait=true
    fi

    log_info "Installing ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    run_command "helm repo add argo https://argoproj.github.io/argo-helm" "ArgoCD Repo Add" || return 0
    run_command "helm repo update" "ArgoCD Repo Update" || return 0
    
    run_command "helm upgrade --install argocd argo/argo-cd -n argocd --set server.service.type=NodePort --set controller.applicationNamespaces=\"\"" "ArgoCD Helm Installation" "argocd" "app.kubernetes.io/name=argocd-server" || return 0
    
    # Wait for server
    log_info "Waiting for ArgoCD server rollout..."
    if ! kubectl rollout status deployment/argocd-server -n argocd --timeout=300s; then
        log_error "ArgoCD server rollout timed out."
        show_troubleshooting "argocd" "app.kubernetes.io/name=argocd-server"
        echo "Select an action:"
        echo "  [s] Skip this check and continue"
        echo "  [a] Abort entire process"
        read -p "Action [s/a]: " choice
        [ "$choice" = "a" ] && exit 0
    else
        log_success "ArgoCD setup complete."
        log_info "ArgoCD Admin Password:"
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
    fi
}

install_nfs_provisioner() {
    ask_action_if_installed "NFS Provisioner" "default" "helm list | grep nfs-subdir-external-provisioner &>/dev/null"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping NFS Provisioner (requested by user)."
        return 0
    fi

    log_info "Installing NFS Subdir External Provisioner..."
    read -p "Enter NFS Server IP (default: 10.10.10.210): " nfs_ip
    nfs_ip=${nfs_ip:-"10.10.10.210"}
    
    read -p "Enter NFS Access Path (default: /srv/nfs/kubedata): " nfs_path
    nfs_path=${nfs_path:-"/srv/nfs/kubedata"}

    run_command "helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/" "NFS Repo Add" || return 0
    run_command "helm repo update" "NFS Repo Update" || return 0
    
    run_command "helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
      --set nfs.server=\"$nfs_ip\" \
      --set nfs.path=\"$nfs_path\" \
      --set storageClass.name=\"nfs-client\" \
      --set storageClass.defaultClass=false \
      --set replicaCount=1" "NFS Helm Installation" || return 0
      
    log_success "NFS Provisioner setup complete."
}

create_docker_registry_secret() {
    log_info "Creating Docker Registry Secret..."
    
    read -p "Enter Namespace (default: automated): " secret_namespace
    secret_namespace=${secret_namespace:-"automated"}
    
    ask_action_if_installed "Docker Secret" "$secret_namespace" "kubectl get secret apt-docker-server -n $secret_namespace &>/dev/null"
    res=$?

    if [ $res -eq 1 ]; then
        log_info "Skipping Docker Secret (requested by user)."
        return 0
    elif [ $res -eq 2 ]; then
        kubectl delete secret apt-docker-server -n "$secret_namespace" --ignore-not-found
    fi

    # Create namespace if it doesn't exist
    kubectl create namespace "$secret_namespace" --dry-run=client -o yaml | kubectl apply -f -

    read -p "Enter Docker Server (default: docker.io): " docker_server
    docker_server=${docker_server:-"docker.io"}
    
    read -p "Enter Docker Username: " docker_user
    
    # Read password with masking
    docker_pass=$(read_password "Enter Docker Password: ")
    
    read -p "Enter Docker Email: " docker_email
    
    if [ -z "$docker_user" ] || [ -z "$docker_pass" ] || [ -z "$docker_email" ]; then
        log_error "Username, Password, and Email are required."
        return 1
    fi
    
    run_command "kubectl create secret docker-registry apt-docker-server \
        --docker-server=\"$docker_server\" \
        --docker-username=\"$docker_user\" \
        --docker-password=\"$docker_pass\" \
        --docker-email=\"$docker_email\" \
        -n \"$secret_namespace\" \
        --dry-run=client -o yaml | kubectl apply -f -" "Docker Registry Secret Creation" || return 0
        
    log_success "Docker Registry secret 'apt-docker-server' created in '$secret_namespace'."
}

install_rollout_extension() {
    log_info "Installing Argo Rollouts Extension for ArgoCD..."
    script_path=""
    if [ -f "kubernetes/install-rollout-extension.sh" ]; then
        script_path="kubernetes/install-rollout-extension.sh"
    elif [ -f "install-rollout-extension.sh" ]; then
        script_path="./install-rollout-extension.sh"
    else
        log_error "install-rollout-extension.sh not found."
        return
    fi
    
    # The script has its own logic, run it with skip/abort support
    run_command "./$script_path" "Argo Rollouts Extension Installation" || return 0
    log_success "Argo Rollouts Extension setup complete."
}

install_all() {
    install_metallb
    install_nginx_ingress
    install_argo_rollouts
    install_metrics_server
    install_local_path_provisioner
    install_argocd
    install_nfs_provisioner
    create_docker_registry_secret
    install_rollout_extension
}

uninstall_argocd() {
    log_info "Uninstalling ArgoCD..."
    helm uninstall argocd -n argocd 2>/dev/null || true
    kubectl delete namespace argocd --ignore-not-found --wait=false
}

uninstall_argo_rollouts() {
    log_info "Uninstalling Argo Rollouts..."
    kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml --ignore-not-found || true
    kubectl delete namespace argo-rollouts --ignore-not-found --wait=false
}

uninstall_nginx_ingress() {
    log_info "Uninstalling NGINX Ingress..."
    kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml --ignore-not-found || true
    kubectl delete namespace ingress-nginx --ignore-not-found --wait=false
}

uninstall_metallb() {
    log_info "Uninstalling MetalLB..."
    kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml --ignore-not-found || true
    kubectl delete namespace metallb-system --ignore-not-found --wait=false
}

uninstall_metrics_server() {
    log_info "Uninstalling Metrics Server..."
    kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found || true
}

uninstall_local_path_provisioner() {
    log_info "Uninstalling Local Path Provisioner..."
    kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml --ignore-not-found || true
    kubectl delete namespace local-path-storage --ignore-not-found --wait=false
}

uninstall_nfs_provisioner() {
    log_info "Uninstalling NFS Provisioner..."
    helm uninstall nfs-subdir-external-provisioner 2>/dev/null || true
}

uninstall_docker_secret() {
    log_info "Removing Docker Registry Secret..."
    read -p "Enter Namespace where secret was created (default: automated): " secret_namespace
    secret_namespace=${secret_namespace:-"automated"}
    kubectl delete secret apt-docker-server -n "$secret_namespace" --ignore-not-found 2>/dev/null || true
}

uninstall_all() {
    echo ""
    echo -e "${RED}WARNING: This will remove ALL components installed by this script.${NC}"
    echo -e "${RED}It will delete namespaces: argocd, argo-rollouts, metallb-system, ingress-nginx, local-path-storage${NC}"
    echo -e "${RED}and helm releases: argocd, nfs-subdir-external-provisioner.${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborting uninstall."
        return
    fi

    uninstall_argocd
    uninstall_argo_rollouts
    uninstall_nginx_ingress
    uninstall_metallb
    uninstall_metrics_server
    uninstall_local_path_provisioner
    uninstall_nfs_provisioner
    uninstall_docker_secret
    
    log_success "Uninstallation commands issued. Namespaces may take a moment to terminate."
}

uninstall_menu() {
    while true; do
        echo ""
        echo -e "${RED}=== Uninstall Components ===${NC}"
        echo "1. Uninstall MetalLB"
        echo "2. Uninstall NGINX Ingress"
        echo "3. Uninstall Argo Rollouts"
        echo "4. Uninstall Metrics Server"
        echo "5. Uninstall Local Path Provisioner"
        echo "6. Uninstall ArgoCD"
        echo "7. Uninstall NFS Provisioner"
        echo "8. Remove Docker Registry Secret"
        echo "9. Uninstall All Components"
        echo "0. Back to Main Menu"
        echo ""
        
        read -p "Select an option to uninstall: " uchoice
        
        case "$uchoice" in
            1) uninstall_metallb ;;
            2) uninstall_nginx_ingress ;;
            3) uninstall_argo_rollouts ;;
            4) uninstall_metrics_server ;;
            5) uninstall_local_path_provisioner ;;
            6) uninstall_argocd ;;
            7) uninstall_nfs_provisioner ;;
            8) uninstall_docker_secret ;;
            9) uninstall_all ;;
            0) break ;;
            *) log_error "Invalid option: $uchoice" ;;
        esac
    done
}

# --- Main Menu ---

show_menu() {
    echo ""
    echo -e "${BLUE}=== Kubernetes Infrastructure Bootstrap ===${NC}"
    echo "1. Install All Components (Recommended)"
    echo "2. Install MetalLB"
    echo "3. Install NGINX Ingress Controller"
    echo "4. Install Argo Rollouts"
    echo "5. Install Metrics Server"
    echo "6. Install Local Path Provisioner"
    echo "7. Install ArgoCD"
    echo "8. Install NFS Provisioner (Interactive)"
    echo "9. Create Docker Registry Secret (Interactive)"
    echo "10. Install Argo Rollouts Extension (Requires ArgoCD)"
    echo "11. Uninstall All Components"
    echo "0. Exit"
    echo ""
}

main() {
    check_prerequisites
    
    while true; do
        show_menu
        read -p "Select an option: " choice
        
        case "$choice" in
            1)
                install_all
                break
                ;;
            2) install_metallb ;;
            3) install_nginx_ingress ;;
            4) install_argo_rollouts ;;
            5) install_metrics_server ;;
            6) install_local_path_provisioner ;;
            7) install_argocd ;;
            8) install_nfs_provisioner ;;
            9) create_docker_registry_secret ;;
            10) install_rollout_extension ;;
            11) uninstall_menu ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option: $choice"
                ;;
        esac
    done
}

# Start interactive menu if no args, or execute based on args if we wanted to add flag support later
# For now, just run main
# Fix for select loop not showing menu after first run if we don't handle it carefully
# Actually 'select' handles the looping. 

main
