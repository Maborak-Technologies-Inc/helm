# Kubernetes Infrastructure Setup

This document describes all the Kubernetes infrastructure components installed and configured for the Amazon Watcher Stack deployment.

## Table of Contents

1. [MetalLB - LoadBalancer Implementation](#metallb---loadbalancer-implementation)
2. [NGINX Ingress Controller](#nginx-ingress-controller)
3. [Argo Rollouts](#argo-rollouts)
4. [ArgoCD](#argocd)
5. [Component Integration](#component-integration)
6. [Verification Commands](#verification-commands)
7. [Troubleshooting](#troubleshooting)

---

## MetalLB - LoadBalancer Implementation

### Overview

MetalLB is a load balancer implementation for bare metal Kubernetes clusters. It provides LoadBalancer services with external IPs in environments that don't have cloud provider load balancers.

### Installation

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
```

### Configuration

**File**: `metallb-config.yaml` (in this directory)

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.40/32
  - 192.168.0.41/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

### Apply Configuration

```bash
# From the helm directory root
kubectl apply -f kubernetes/metallb-config.yaml

# Or from the kubernetes directory
cd kubernetes
kubectl apply -f metallb-config.yaml
```

### IP Address Pool

- **IP Range**: `192.168.0.40/32` and `192.168.0.41/32`
- **Network**: Must be accessible from your host machine
- **Current Assignment**: `192.168.0.40` assigned to NGINX Ingress Controller

### Verification

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP address pool
kubectl get ipaddresspool -n metallb-system

# Check L2Advertisement
kubectl get l2advertisement -n metallb-system

# Verify LoadBalancer service got an IP
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Important Notes

- IP addresses must be available on your network
- IPs should be in the same subnet as your host machine
- MetalLB uses Layer 2 mode (ARP/NDP) for IP assignment
- Only works in local/bare metal clusters (not cloud providers)

---

## NGINX Ingress Controller

### Overview

NGINX Ingress Controller provides HTTP/HTTPS routing to services based on hostnames and paths. It acts as a reverse proxy and load balancer.

### Installation

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

### Configuration

**Service Type**: LoadBalancer (uses MetalLB for IP assignment)

**External Traffic Policy**: Changed to `Cluster` for proper routing

```bash
# Fix external traffic policy (required for MetalLB)
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
```

### Ingress Class

- **Name**: `nginx`
- **Controller**: `k8s.io/ingress-nginx`

### Access

- **LoadBalancer IP**: `192.168.0.40` (assigned by MetalLB)
- **NodePort**: `30487` (HTTP), `30232` (HTTPS)
- **Port-Forward**: `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80`

### Verification

```bash
# Check Ingress Controller pod
kubectl get pods -n ingress-nginx

# Check Ingress Controller service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check Ingress resources
kubectl get ingress -A

# Test Ingress routing
curl -H "Host: api.amazon-watcher.local" http://192.168.0.40/health
```

### Ingress Resources

The Helm chart creates Ingress resources for:
- **Backend**: `api.amazon-watcher.local` → Backend service (port 9000)
- **UI**: `ui.amazon-watcher.local` → UI service (port 80)

**Note**: Ingress resources are only created when `ingress.enabled=true` AND `ingress.className` is set.

---

## Argo Rollouts

### Overview

Argo Rollouts is a Kubernetes controller that provides advanced deployment strategies like canary and blue-green deployments, with automatic rollback capabilities.

### Installation

```bash
# Create namespace
kubectl create namespace argo-rollouts

# Install Argo Rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### Verification

```bash
# Check Argo Rollouts controller
kubectl get pods -n argo-rollouts

# Check Rollout CRD
kubectl get crd rollouts.argoproj.io
```

### Usage in Helm Chart

The screenshot service uses Argo Rollout instead of Deployment:

- **Template**: `charts/amazon-watcher-stack/templates/screenshot-rollout.yaml`
- **API Version**: `argoproj.io/v1alpha1`
- **Kind**: `Rollout`

### Configuration

In `charts/amazon-watcher-stack/values.yaml`:

```yaml
screenshot:
  rollout:
    revisionHistoryLimit: 10
    # Optional: Canary or Blue-Green strategy
    # strategy:
    #   canary:
    #     steps:
    #     - setWeight: 10
    #     - pause: {}
    #     - setWeight: 50
    #     - pause: {duration: 5m}
    #     - setWeight: 100
```

### Benefits

- Advanced deployment strategies (canary, blue-green)
- Automatic rollback on metrics
- Progressive delivery
- Traffic splitting capabilities
- Integration with service mesh (Istio/Linkerd)

---

## ArgoCD

### Overview

ArgoCD is a GitOps continuous delivery tool for Kubernetes. It automatically syncs applications from Git repositories.

### Installation

See `docs/ZABBIX_ARGOCD_SETUP.md` for detailed ArgoCD installation instructions.

### Application Configuration

**Application Name**: `test`  
**Namespace**: `argocd`  
**Chart Path**: `charts/amazon-watcher-stack`  
**Target Namespace**: `default` (or `automated`)

### Sync Policy

- **Auto-sync**: Enabled
- **Self-heal**: Enabled
- **Auto-prune**: Enabled

### Access

- **Port-forward**: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
- **URL**: `https://localhost:8080` (via port-forward)

---

## Component Integration

### How Components Work Together

```
┌─────────────────────────────────────────────────────────┐
│                    User Request                          │
│              http://api.amazon-watcher.local            │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              NGINX Ingress Controller                    │
│              IP: 192.168.0.40 (MetalLB)                 │
│              Port: 80                                   │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                    Ingress Resource                     │
│         api.amazon-watcher.local → Backend Service      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Backend Service (ClusterIP)                 │
│         test-amazon-watcher-stack-backend:9000          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│            Backend Pods (Deployment)                     │
│         Managed by Kubernetes                            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│         Screenshot Service (Rollout)                    │
│         Managed by Argo Rollouts                         │
│         Scaled by HPA                                    │
└─────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **External Request** → `http://api.amazon-watcher.local`
2. **DNS Resolution** → `192.168.0.40` (via /etc/hosts or DNS)
3. **NGINX Ingress** → Routes based on Host header
4. **Service** → Routes to backend pods
5. **Pods** → Handle the request

### Scaling Flow

1. **HPA** monitors CPU/Memory metrics
2. **HPA** calculates desired replicas
3. **HPA** updates Rollout/Deployment spec.replicas
4. **Rollout/Deployment** creates/deletes pods
5. **Service** automatically routes to new pods

---

## Verification Commands

### Check All Components

```bash
# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingressclass

# Argo Rollouts
kubectl get pods -n argo-rollouts
kubectl get crd rollouts.argoproj.io

# ArgoCD
kubectl get pods -n argocd
kubectl get application -n argocd

# Application Resources
kubectl get rollout -n default
kubectl get hpa -n default
kubectl get ingress -n default
kubectl get svc -n default
```

### Test Ingress

```bash
# Add to /etc/hosts
echo "192.168.0.40  api.amazon-watcher.local" | sudo tee -a /etc/hosts
echo "192.168.0.40  ui.amazon-watcher.local" | sudo tee -a /etc/hosts

# Test backend
curl http://api.amazon-watcher.local/health

# Test UI
curl http://ui.amazon-watcher.local/
```

### Check HPA

```bash
# Get HPA status
kubectl get hpa test-amazon-watcher-stack-screenshot -n default

# Describe HPA
kubectl describe hpa test-amazon-watcher-stack-screenshot -n default

# Watch HPA scaling
kubectl get hpa test-amazon-watcher-stack-screenshot -n default -w
```

### Check Rollout

```bash
# Get Rollout status
kubectl get rollout test-amazon-watcher-stack-screenshot -n default

# Describe Rollout
kubectl describe rollout test-amazon-watcher-stack-screenshot -n default

# Get Rollout history (requires kubectl argo rollouts plugin)
kubectl argo rollouts get rollout test-amazon-watcher-stack-screenshot -n default
```

---

## Troubleshooting

### MetalLB Issues

**Problem**: LoadBalancer service stuck in "Pending"

**Solution**:
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP address pool
kubectl get ipaddresspool -n metallb-system -o yaml

# Verify IPs are in correct network range
ping 192.168.0.40
```

**Problem**: IP not accessible from host

**Solution**:
- Ensure IPs are in the same subnet as your host
- Check network routes
- Verify firewall rules

### Ingress Issues

**Problem**: Connection timeout or empty reply

**Solution**:
```bash
# Check Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Fix external traffic policy
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'

# Verify Ingress resources
kubectl get ingress -n default -o yaml
```

**Problem**: Ingress not getting an address

**Solution**:
- Ensure Ingress Controller is running
- Check `ingressClassName` is set correctly
- Verify Ingress resources have proper rules

### Argo Rollouts Issues

**Problem**: Rollout not found

**Solution**:
```bash
# Verify Argo Rollouts is installed
kubectl get pods -n argo-rollouts

# Check CRD exists
kubectl get crd rollouts.argoproj.io

# Reinstall if needed
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

**Problem**: Rollout stuck in progress

**Solution**:
```bash
# Check Rollout status
kubectl describe rollout <rollout-name> -n default

# Check pod status
kubectl get pods -n default -l app.kubernetes.io/component=screenshot

# Abort rollout if needed (requires kubectl argo rollouts plugin)
kubectl argo rollouts abort <rollout-name> -n default
```

### HPA Issues

**Problem**: HPA not scaling

**Solution**:
```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# Check HPA status
kubectl describe hpa <hpa-name> -n default

# Verify resource requests are set
kubectl get rollout <rollout-name> -n default -o yaml | grep requests
```

**Problem**: HPA shows "unknown" metrics

**Solution**:
- Install metrics server: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
- Ensure resource requests are configured in pod spec

---

## Configuration Files

### MetalLB Configuration

**Location**: `kubernetes/metallb-config.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.40/32
  - 192.168.0.41/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

### Helm Chart Configuration

**Location**: `charts/amazon-watcher-stack/values.yaml`

Key sections:
- `ingress.enabled`: Enable/disable Ingress
- `ingress.className`: Ingress class name (e.g., "nginx")
- `screenshot.rollout`: Argo Rollout configuration
- `screenshot.autoscaling`: HPA configuration

---

## Quick Reference

### Install All Components

```bash
# 1. MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl apply -f kubernetes/metallb-config.yaml

# 2. NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'

# 3. Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# 4. Metrics Server (for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Uninstall Components

```bash
# MetalLB
kubectl delete -f kubernetes/metallb-config.yaml
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# NGINX Ingress
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Argo Rollouts
kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

---

## Version Information

- **MetalLB**: v0.14.5
- **NGINX Ingress Controller**: v1.14.1
- **Argo Rollouts**: Latest (from GitHub releases)
- **Kubernetes**: v1.31.1

---

## Additional Resources

- [MetalLB Documentation](https://metallb.universe.tf/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

## Last Updated

January 20, 2026
