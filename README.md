# Helm Charts Repository

A production-ready Helm charts repository providing enterprise-grade Kubernetes deployments for monitoring, observability, and application stacks. This repository follows GitOps best practices and is designed for automated deployment workflows with Argo CD.

## Repository Overview

This repository contains standardized Helm charts for deploying complex application stacks on Kubernetes. All charts are designed with production-grade defaults, security best practices, and operational excellence in mind.

### Intended Use Cases

- **Production Deployments**: Charts are tested and validated for production workloads
- **GitOps Workflows**: Full compatibility with Argo CD and other GitOps tools
- **Multi-Environment Management**: Support for environment-specific configurations
- **Enterprise Operations**: Designed for SRE teams managing large-scale Kubernetes infrastructure

### Design Philosophy

- **Reliability**: Health checks, resource limits, and graceful shutdowns configured by default
- **Scalability**: Horizontal Pod Autoscaling (HPA) support and configurable resource requirements
- **Security**: RBAC, service accounts, and secrets management built-in
- **GitOps-Ready**: All charts support declarative deployment via Argo CD
- **Observability**: Structured logging, health endpoints, and metrics exposure

## Available Helm Charts

| Chart Name | Description | Kubernetes Versions | Key Features | Production Readiness |
|------------|-------------|---------------------|--------------|---------------------|
| `amazon-watcher-stack` | Complete Amazon product monitoring stack with backend API, web UI, screenshot service, and PostgreSQL database | 1.24+ | Multi-service architecture, Ingress support, Argo Rollouts, HPA, persistent storage | Yes |
| `zabbix` | Zabbix monitoring solution with server, web UI, and MariaDB database | 1.24+ | Full Zabbix stack, persistent storage, RBAC, configurable resources | Yes |

## Chart Details

### amazon-watcher-stack

#### Purpose and Architecture

The `amazon-watcher-stack` chart deploys a complete microservices-based application for monitoring Amazon product availability and price tracking. The architecture consists of four primary components:

- **Backend API**: RESTful API service built on FastAPI/Uvicorn, handling product monitoring logic, database operations, and screenshot orchestration
- **Web UI**: React-based frontend application served via NGINX
- **Screenshot Service**: Headless browser service for capturing product pages using Playwright/Chromium
- **PostgreSQL Database**: Stateful database for storing product data, price history, and application state

All components are deployed as separate Kubernetes resources with independent scaling and configuration capabilities.

#### Key Features

- **Multi-Service Deployment**: Independent Deployments for backend, UI, and screenshot services
- **Argo Rollouts Integration**: Screenshot service uses Argo Rollouts for advanced deployment strategies (canary, blue-green)
- **Horizontal Pod Autoscaling**: Configurable HPA for screenshot service based on CPU and memory metrics
- **Ingress Support**: Optional Kubernetes Ingress resources with configurable ingress class
- **Persistent Storage**: PVC support for screenshot storage and database data
- **Health Checks**: Configurable liveness and readiness probes for all services
- **Resource Management**: CPU and memory limits/requests configurable per component
- **Service Account**: Dedicated service account with configurable RBAC
- **Secrets Management**: Kubernetes Secrets for database credentials and JWT tokens

#### Configuration Highlights

The chart exposes comprehensive configuration through `values.yaml`:

- **Component Toggles**: Enable/disable individual services (backend, UI, screenshot, database)
- **Replica Configuration**: Independent replica counts per service
- **Image Management**: Configurable container images with pull policies
- **Resource Allocation**: Per-service CPU and memory limits/requests
- **Ingress Configuration**: Domain names, TLS settings, and ingress class selection
- **Database Configuration**: PostgreSQL version, credentials, storage, and connection pooling
- **Environment Variables**: Extensive environment variable configuration for all services
- **Autoscaling**: HPA configuration with min/max replicas and target utilization
- **Rollout Strategy**: Optional canary or blue-green deployment strategies

#### Security Considerations

- Service accounts with least-privilege principles
- Secrets stored in Kubernetes Secrets (not in values.yaml)
- Configurable security contexts for pods and containers
- Network policies support via service selectors
- TLS/SSL support for Ingress resources
- JWT-based authentication for backend API

#### Resource Requirements

Minimum cluster resources for a standard deployment:

- **Backend**: 512Mi memory, 500m CPU (requests)
- **UI**: 512Mi memory, 100m CPU (requests)
- **Screenshot**: 1Gi memory, 500m CPU (requests)
- **Database**: 512Mi memory, 500m CPU (requests)
- **Storage**: 10Gi for database, 5Gi for screenshot storage

Total minimum: ~3Gi memory, ~1.6 CPU cores, 15Gi storage.

#### Dependencies

- **Kubernetes**: 1.24 or higher
- **Argo Rollouts**: Required for screenshot service (CRD: `rollouts.argoproj.io`)
- **Ingress Controller**: Optional, required if `ingress.enabled=true` (NGINX, Traefik, etc.)
- **Storage Class**: Required for persistent volumes (database and screenshot storage)
- **Metrics Server**: Required for HPA functionality

### zabbix

#### Purpose and Architecture

The `zabbix` chart deploys a complete Zabbix monitoring solution consisting of:

- **Zabbix Server**: Core monitoring engine processing metrics and triggers
- **Zabbix UI**: Web-based user interface for configuration and visualization
- **MariaDB**: Relational database storing Zabbix configuration and historical data

The chart uses StatefulSets for database persistence and Deployments for stateless components.

#### Key Features

- **Complete Zabbix Stack**: Server, UI, and database in a single chart
- **Persistent Storage**: PersistentVolume and PersistentVolumeClaim for MariaDB data
- **RBAC Configuration**: Service accounts, roles, and role bindings
- **Configurable Resources**: CPU and memory limits per component
- **Replica Scaling**: Independent replica configuration for server and UI
- **ConfigMap Management**: Centralized configuration via ConfigMap

#### Configuration Highlights

- **Replica Management**: Separate replica counts for server, UI, and MariaDB
- **Resource Allocation**: Per-component resource limits and requests
- **Storage Configuration**: Persistent volume size and storage class selection
- **Database Settings**: MariaDB version and configuration options
- **Service Configuration**: Service types and port configurations

#### Security Considerations

- RBAC with dedicated service accounts
- Database credentials in Kubernetes Secrets
- Network isolation via service selectors
- Configurable security contexts

#### Resource Requirements

Minimum cluster resources:

- **Zabbix Server**: 512Mi memory, 200m CPU (requests)
- **Zabbix UI**: 256Mi memory, 100m CPU (requests)
- **MariaDB**: Variable based on data volume

#### Dependencies

- **Kubernetes**: 1.24 or higher
- **Storage Class**: Required for MariaDB persistent storage
- **PersistentVolume**: Cluster-scoped resource (requires appropriate permissions)

## Installation with Helm

### Prerequisites

- Kubernetes cluster (1.24 or higher)
- Helm 3.x installed
- `kubectl` configured with cluster access
- Appropriate RBAC permissions for creating resources in target namespace

### Add Helm Repository

This repository can be used directly from Git or packaged as a Helm repository. For Git-based usage:

```bash
# Clone the repository
git clone git@github.com:Maborak-Technologies-Inc/helm.git
cd helm

# Install directly from local chart
helm install <release-name> ./charts/<chart-name> \
  --namespace <namespace> \
  --create-namespace
```

### Install Example

**Amazon Watcher Stack:**

```bash
helm install amazon-watcher-stack ./charts/amazon-watcher-stack \
  --namespace production \
  --create-namespace \
  --set ingress.className=nginx \
  --set ingress.enabled=true
```

**Zabbix:**

```bash
helm install zabbix ./charts/zabbix \
  --namespace monitoring \
  --create-namespace \
  --set storage.storageClass=fast-ssd
```

### Upgrade Example

```bash
# Upgrade with new values
helm upgrade amazon-watcher-stack ./charts/amazon-watcher-stack \
  --namespace production \
  --set backend.replicas=3 \
  --set ui.replicas=2

# Upgrade with values file
helm upgrade zabbix ./charts/zabbix \
  --namespace monitoring \
  -f values-production.yaml
```

### Uninstall Example

```bash
helm uninstall amazon-watcher-stack --namespace production
helm uninstall zabbix --namespace monitoring
```

### Versioning and Values Overrides

Charts follow semantic versioning (SemVer). Override default values using:

- **Command-line flags**: `--set key=value`
- **Values files**: `-f values.yaml` or `--values values.yaml`
- **Multiple sources**: Combine multiple `-f` flags (later files override earlier ones)

Example with multiple overrides:

```bash
helm install amazon-watcher-stack ./charts/amazon-watcher-stack \
  --namespace production \
  -f charts/amazon-watcher-stack/values.yaml \
  -f values-production.yaml \
  --set ingress.enabled=true
```

## GitOps Deployment with Argo CD

### GitOps Approach

This repository is designed for GitOps workflows where the desired state is declared in Git and automatically synchronized to the cluster. Argo CD monitors the repository and ensures the cluster matches the declared configuration.

### Production-Grade Argo CD Application Manifest

**Example: Amazon Watcher Stack**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: amazon-watcher-stack-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: git@github.com:Maborak-Technologies-Inc/helm.git
    targetRevision: main
    path: charts/amazon-watcher-stack
    helm:
      valueFiles:
      - values.yaml
      parameters:
      - name: ingress.enabled
        value: "true"
      - name: ingress.className
        value: "nginx"
      - name: backend.replicas
        value: "3"
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  # Ignore replicas field for Rollouts when HPA is managing them
  ignoreDifferences:
    - group: argoproj.io
      kind: Rollout
      jsonPointers:
        - /spec/replicas
```

**Example: Zabbix**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: zabbix-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:Maborak-Technologies-Inc/helm.git
    targetRevision: main
    path: charts/zabbix
    helm:
      parameters:
      - name: storage.storageClass
        value: "fast-ssd"
      - name: replicas.zabbixServer
        value: "2"
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Deploying via Argo CD CLI

```bash
# Create application
argocd app create amazon-watcher-stack-prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/amazon-watcher-stack \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production \
  --sync-policy automated \
  --self-heal \
  --auto-prune

# Sync application
argocd app sync amazon-watcher-stack-prod
```

### Namespace Handling

Argo CD can automatically create namespaces if `CreateNamespace=true` is set in sync options. Ensure the Argo CD service account has appropriate permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-application-controller
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["create", "get", "list"]
```

## Configuration & Customization

### Overriding Values

**Method 1: Values File (Recommended for GitOps)**

Create environment-specific values files:

```yaml
# values-production.yaml
backend:
  replicas: 3
  resources:
    limits:
      memory: 2Gi
      cpu: 2000m
ingress:
  enabled: true
  className: "nginx"
```

Apply via Helm or Argo CD:

```bash
helm install amazon-watcher-stack ./charts/amazon-watcher-stack \
  -f values-production.yaml
```

**Method 2: Helm Parameters (Quick Overrides)**

```bash
helm install amazon-watcher-stack ./charts/amazon-watcher-stack \
  --set backend.replicas=3 \
  --set ingress.enabled=true
```

**Method 3: Argo CD Parameters**

Parameters set in Argo CD Application manifest override values.yaml:

```yaml
spec:
  source:
    helm:
      parameters:
      - name: backend.replicas
        value: "3"
```

### Environment-Specific Configurations

**Development:**

```yaml
backend:
  replicas: 1
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
ingress:
  enabled: false
```

**Production:**

```yaml
backend:
  replicas: 3
  resources:
    limits:
      memory: 2Gi
      cpu: 2000m
ingress:
  enabled: true
  className: "nginx"
  tls:
    enabled: true
screenshot:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
```

### Best Practices for Production

1. **Resource Limits**: Always set resource limits to prevent resource exhaustion
2. **Health Checks**: Enable and configure appropriate health check timeouts
3. **Replica Counts**: Use HPA for variable workloads, fixed replicas for stable services
4. **Storage**: Use appropriate storage classes with backup strategies
5. **Secrets**: Never commit secrets to Git; use external secret management
6. **Ingress**: Enable TLS/SSL for all production Ingress resources
7. **Monitoring**: Configure appropriate resource requests for monitoring overhead
8. **Namespaces**: Isolate environments using separate namespaces

## Versioning & Compatibility

### Helm Chart Versioning Strategy

Charts follow [Semantic Versioning](https://semver.org/) (SemVer):

- **Major version** (X.0.0): Breaking changes requiring manual intervention
- **Minor version** (0.X.0): New features, backward compatible
- **Patch version** (0.0.X): Bug fixes, backward compatible

Chart versions are independent of application versions. The `appVersion` field in Chart.yaml indicates the application version the chart deploys.

### Kubernetes Compatibility Guarantees

- **Minimum Kubernetes Version**: 1.24
- **API Compatibility**: Charts use stable Kubernetes APIs (apps/v1, networking.k8s.io/v1)
- **Deprecation Policy**: Charts are updated before Kubernetes API deprecations take effect
- **Testing**: Charts are tested against the minimum supported version and latest stable version

### Version Support Matrix

| Chart | Chart Version | Kubernetes | Status |
|-------|--------------|------------|--------|
| amazon-watcher-stack | 0.1.0 | 1.24+ | Supported |
| zabbix | 0.1.1 | 1.24+ | Supported |

## Security & Compliance

### Secure Defaults

All charts implement security best practices by default:

- **Non-root Containers**: Security contexts configured to run as non-root users where possible
- **Read-only Root Filesystems**: Configurable read-only root filesystems for stateless containers
- **Drop Capabilities**: Unnecessary Linux capabilities dropped by default
- **Resource Limits**: CPU and memory limits prevent resource exhaustion attacks
- **Network Policies**: Service selectors support network policy implementation

### RBAC Considerations

Charts create dedicated service accounts with minimal required permissions:

- **Service Accounts**: Created per chart instance with unique names
- **Role Bindings**: Cluster-scoped or namespace-scoped based on requirements
- **Least Privilege**: Service accounts granted only necessary permissions

Example RBAC configuration:

```yaml
serviceAccount:
  create: true
  annotations: {}
  name: ""
```

### Secrets Handling Recommendations

**Do:**

- Store secrets in Kubernetes Secrets (not in values.yaml)
- Use external secret management systems (Sealed Secrets, External Secrets Operator, Vault)
- Rotate secrets regularly
- Use separate secrets per environment

**Don't:**

- Commit secrets to Git repositories
- Use default passwords in production
- Share secrets across environments
- Store secrets in ConfigMaps

**Example Secret Management:**

```bash
# Create secret from file
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=$(openssl rand -base64 32) \
  --namespace production

# Reference in values.yaml via existingSecret
database:
  existingSecret: db-credentials
```

## Contributing

### Contribution Guidelines

Contributions to this repository are welcome. All contributions must follow these guidelines:

1. **Code Quality**: All Helm templates must pass `helm lint`
2. **Testing**: Test charts in a clean Kubernetes environment before submitting
3. **Documentation**: Update README.md and chart-specific documentation
4. **Versioning**: Follow SemVer for chart version updates
5. **Security**: No secrets or sensitive data in commits

### Linting and Testing

**Lint Charts:**

```bash
helm lint ./charts/amazon-watcher-stack
helm lint ./charts/zabbix
```

**Template Validation:**

```bash
helm template amazon-watcher-stack ./charts/amazon-watcher-stack \
  --debug \
  --dry-run
```

**Dry-run Install:**

```bash
helm install amazon-watcher-stack ./charts/amazon-watcher-stack \
  --namespace test \
  --dry-run \
  --debug
```

### Review Expectations

- All pull requests require review from maintainers
- Charts must pass linting and template validation
- Documentation updates required for configuration changes
- Breaking changes require migration guides

## Support & Maintenance

### Issue Handling

Issues are tracked in the repository's issue tracker. Priority is assigned based on:

- **Critical**: Security vulnerabilities, data loss risks, complete service outages
- **High**: Feature breakage, significant performance degradation
- **Medium**: Minor bugs, documentation improvements
- **Low**: Enhancement requests, non-critical improvements

### Response Expectations

- **Critical Issues**: Response within 4 business hours, resolution target 24 hours
- **High Priority**: Response within 1 business day, resolution target 1 week
- **Medium Priority**: Response within 3 business days, resolution target 2 weeks
- **Low Priority**: Response within 1 week, resolution based on roadmap

### Maintenance Windows

Chart updates and security patches are released on a regular schedule:

- **Security Patches**: Released as needed, typically within 48 hours of vulnerability disclosure
- **Feature Releases**: Monthly release cycle for new features and enhancements
- **Bug Fixes**: Released as patches (0.0.X) when issues are identified and resolved

### Long-term Support

- **Active Support**: Charts receive updates and security patches for 12 months from release
- **Security-only Support**: Critical security patches for an additional 6 months
- **Deprecation Notice**: 3 months advance notice before chart deprecation

---

## RUNBOOK

This section provides operational procedures for SRE and DevOps teams managing the Helm charts in production environments.

### Table of Contents

- [Health Checks & Monitoring](#health-checks--monitoring)
- [Scaling Operations](#scaling-operations)
- [Rollout Management](#rollout-management)
- [Image Updates](#image-updates)
- [Emergency Procedures](#emergency-procedures)
- [Database Operations](#database-operations)
- [CLI Operations](#cli-operations)
- [Troubleshooting Procedures](#troubleshooting-procedures)
- [Performance Tuning](#performance-tuning)

---

### Health Checks & Monitoring

#### Check Application Health

```bash
# Check all pods status
kubectl get pods -n <namespace> -l app.kubernetes.io/instance=<release-name>

# Check specific component
kubectl get pods -n <namespace> -l app.kubernetes.io/component=backend
kubectl get pods -n <namespace> -l app.kubernetes.io/component=ui
kubectl get pods -n <namespace> -l app.kubernetes.io/component=screenshot

# Check pod health (ready, running, restarts)
kubectl get pods -n <namespace> -o wide

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs for errors
kubectl logs -n <namespace> -l app.kubernetes.io/component=backend --tail=100 | grep -i error
```

#### Check Service Endpoints

```bash
# Check services
kubectl get svc -n <namespace>

# Check service endpoints
kubectl get endpoints -n <namespace>

# Test backend health endpoint
kubectl exec -n <namespace> <backend-pod> -- curl -f http://localhost:9000/health

# Test from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>.<namespace>.svc.cluster.local:9000/health
```

#### Check ArgoCD Application Status

```bash
# Get application status
argocd app get <app-name>

# Check sync status
argocd app get <app-name> -o jsonpath='{.status.sync.status}'

# Check health status
argocd app get <app-name> -o jsonpath='{.status.health.status}'

# View application resources
argocd app manifests <app-name>

# Check sync history
argocd app history <app-name>
```

#### Monitor Resource Usage

```bash
# Check CPU and memory usage
kubectl top pods -n <namespace>

# Check node resources
kubectl top nodes

# Check HPA status
kubectl get hpa -n <namespace>

# Watch HPA scaling in real-time
watch -n 5 'kubectl get hpa -n <namespace>'
```

---

### Scaling Operations

#### Manual Scaling

**Using Helm:**
```bash
# Scale backend to 3 replicas
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set backend.replicas=3

# Scale UI to 2 replicas
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set ui.replicas=2
```

**Using kubectl (temporary, will be overridden by ArgoCD):**
```bash
# Scale Rollout directly
kubectl scale rollout <release-name>-backend -n <namespace> --replicas=3

# Scale Deployment (if not using Rollout)
kubectl scale deployment <release-name>-backend -n <namespace> --replicas=3
```

**Using ArgoCD:**
```bash
# Update values.yaml in Git, then sync
argocd app sync <app-name>

# Or set parameter directly (not recommended for GitOps)
argocd app set <app-name> --helm-set backend.replicas=3
```

#### HPA Configuration

**Check Current HPA Status:**
```bash
# Get HPA details
kubectl get hpa -n <namespace>
kubectl describe hpa <release-name>-screenshot -n <namespace>

# Check scaling events
kubectl get events -n <namespace> --field-selector involvedObject.name=<hpa-name> --sort-by='.lastTimestamp'
```

**HPA Thresholds:**
- **Target CPU**: 50% of request (default)
- **Min Replicas**: 1 (default)
- **Max Replicas**: 10 (default)
- **Scale Up**: Triggers when CPU > 50% for 15+ seconds
- **Scale Down**: Triggers when CPU < 50% for 5+ minutes

**Update HPA Configuration:**
```bash
# Update via Helm values.yaml
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set screenshot.autoscaling.minReplicas=2 \
  --set screenshot.autoscaling.maxReplicas=20 \
  --set screenshot.autoscaling.targetCPUUtilizationPercentage=70
```

**Disable HPA Temporarily:**
```bash
# Set global.hpa to false
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set global.hpa=false
```

---

### Rollout Management

#### Check Rollout Status

```bash
# Get Rollout status
kubectl get rollout <release-name>-screenshot -n <namespace>

# Detailed Rollout info
kubectl describe rollout <release-name>-screenshot -n <namespace>

# Using Argo Rollouts plugin (if installed)
kubectl argo rollouts get rollout <release-name>-screenshot -n <namespace>

# Check Rollout history
kubectl argo rollouts history <release-name>-screenshot -n <namespace>
```

#### Rollout Operations

**Pause Rollout:**
```bash
# Pause canary rollout
kubectl argo rollouts pause <release-name>-screenshot -n <namespace>

# Resume rollout
kubectl argo rollouts resume <release-name>-screenshot -n <namespace>
```

**Promote Canary:**
```bash
# Promote canary to stable (skip remaining steps)
kubectl argo rollouts promote <release-name>-screenshot -n <namespace>
```

**Abort Rollout:**
```bash
# Abort current rollout and rollback
kubectl argo rollouts abort <release-name>-screenshot -n <namespace>
```

**Rollback:**
```bash
# Rollback to previous revision
kubectl argo rollouts undo <release-name>-screenshot -n <namespace>

# Rollback to specific revision
kubectl argo rollouts undo <release-name>-screenshot -n <namespace> --to-revision=2
```

#### Rollout Strategy Configuration

**Canary Strategy (Progressive):**
```yaml
strategy:
  canary:
    steps:
    - setWeight: 10
    - pause: {}
    - setWeight: 50
    - pause: {duration: 5m}
    - setWeight: 100
```

**Blue-Green Strategy:**
```yaml
strategy:
  blueGreen:
    activeService: screenshot
    previewService: screenshot-preview
    autoPromotionEnabled: false
    scaleDownDelaySeconds: 30
```

---

### Image Updates

#### Manual Image Update

**Method 1: Update values.yaml in Git (Recommended for GitOps):**
```bash
# Edit values.yaml
vim charts/amazon-watcher-stack/values.yaml
# Change: backend.image.tag: "apt-backend-0.2"

# Commit and push
git add charts/amazon-watcher-stack/values.yaml
git commit -m "Update backend image to apt-backend-0.2"
git push

# ArgoCD will auto-sync (if enabled)
# Or manually sync
argocd app sync <app-name>
```

**Method 2: Helm upgrade:**
```bash
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set backend.image.tag=apt-backend-0.2 \
  --set backend.image.pullPolicy=Always
```

**Method 3: ArgoCD parameter (temporary):**
```bash
argocd app set <app-name> --helm-set backend.image.tag=apt-backend-0.2
argocd app sync <app-name>
```

#### Verify Image Update

```bash
# Check current image
kubectl get rollout <release-name>-backend -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pod images
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Force image pull (if using same tag)
kubectl rollout restart rollout <release-name>-backend -n <namespace>
```

#### Automated Image Updates (ArgoCD Image Updater)

**Setup ArgoCD Image Updater:**
```yaml
# In ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  annotations:
    argocd-image-updater.argoproj.io/image-list: backend=maborak/platform
    argocd-image-updater.argoproj.io/backend.update-strategy: semver
    argocd-image-updater.argoproj.io/backend.allow-tags: regexp:^apt-backend-.*$
spec:
  # ... rest of application spec
```

---

### Emergency Procedures

#### Pod Restart

```bash
# Restart all pods in a Rollout
kubectl rollout restart rollout <release-name>-backend -n <namespace>

# Restart specific pod
kubectl delete pod <pod-name> -n <namespace>

# Force delete pod (if stuck)
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

#### Service Recovery

**If Backend is Down:**
```bash
# 1. Check pod status
kubectl get pods -n <namespace> -l app.kubernetes.io/component=backend

# 2. Check logs
kubectl logs -n <namespace> -l app.kubernetes.io/component=backend --tail=100

# 3. Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep backend

# 4. Restart if needed
kubectl rollout restart rollout <release-name>-backend -n <namespace>

# 5. Scale up if needed
kubectl scale rollout <release-name>-backend -n <namespace> --replicas=3
```

**If Database is Down:**
```bash
# 1. Check StatefulSet
kubectl get statefulset <release-name>-database -n <namespace>

# 2. Check database pod
kubectl describe pod <release-name>-database-0 -n <namespace>

# 3. Check PVC
kubectl get pvc -n <namespace>

# 4. Check database logs
kubectl logs <release-name>-database-0 -n <namespace> --tail=100
```

#### Rollback Emergency

**Quick Rollback:**
```bash
# Rollback to previous revision
kubectl argo rollouts undo <release-name>-screenshot -n <namespace>

# Or via Helm
helm rollback <release-name> <revision-number> -n <namespace>

# Or via ArgoCD
argocd app rollback <app-name> <revision-id>
```

**Complete Application Rollback:**
```bash
# 1. Get application history
argocd app history <app-name>

# 2. Rollback to previous sync
argocd app rollback <app-name> <revision-id>

# 3. Verify rollback
kubectl get pods -n <namespace>
```

#### Disable Auto-Sync (Emergency)

```bash
# Disable auto-sync to prevent further changes
argocd app set <app-name> --sync-policy none

# Re-enable after fixing issue
argocd app set <app-name> --sync-policy automated
```

---

### Database Operations

#### Database Connection

```bash
# Port-forward to database
kubectl port-forward svc/<release-name>-database -n <namespace> 5432:5432

# Connect using psql
psql -h localhost -U postgres -d <database-name>

# Or exec into database pod
kubectl exec -it <release-name>-database-0 -n <namespace> -- psql -U postgres
```

#### Database Backup

```bash
# Create backup
kubectl exec <release-name>-database-0 -n <namespace> -- \
  pg_dump -U postgres <database-name> > backup-$(date +%Y%m%d).sql

# Or using PVC snapshot (if supported)
kubectl get pvc <release-name>-database-pvc -n <namespace> -o yaml > pvc-backup.yaml
```

#### Database Restore

```bash
# Restore from backup
kubectl exec -i <release-name>-database-0 -n <namespace> -- \
  psql -U postgres <database-name> < backup-20260120.sql
```

#### Database Migration

```bash
# Run migration using CLI helper
./kubernetes/run-backend-cli-helm.sh "python manage.py migrate"

# Or using Alembic
./kubernetes/run-backend-cli-helm.sh "python -m alembic upgrade head"
```

---

### CLI Operations

#### Run CLI Commands

**Using Helper Script:**
```bash
# Run command in CLI Rollout pod
./kubernetes/run-backend-cli-helm.sh "python cli.py monitor run --batch-limit=500"

# With custom namespace/release
NAMESPACE=automated RELEASE_NAME=test-apt \
  ./kubernetes/run-backend-cli-helm.sh "python manage.py migrate"
```

**Direct kubectl exec:**
```bash
# Get CLI pod
CLI_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/component=backend-cli -o jsonpath='{.items[0].metadata.name}')

# Execute command
kubectl exec -n <namespace> $CLI_POD -c backend-cli -- \
  /bin/sh -c "cd /app && python cli.py monitor run"
```

#### Check CLI Status

```bash
# Check CLI pods
kubectl get pods -n <namespace> -l app.kubernetes.io/component=backend-cli

# Check CLI logs
kubectl logs -n <namespace> -l app.kubernetes.io/component=backend-cli --tail=100

# Check CLI Rollout
kubectl get rollout <release-name>-backend-cli -n <namespace>
```

---

### Troubleshooting Procedures

#### Pod Not Starting

**Diagnosis:**
```bash
# Check pod status
kubectl get pod <pod-name> -n <namespace> -o yaml

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous  # If pod crashed

# Check init containers
kubectl logs <pod-name> -n <namespace> -c <init-container-name>
```

**Common Issues:**
- **ImagePullBackOff**: Check image name/tag, image pull secrets
- **CrashLoopBackOff**: Check application logs, health checks
- **Pending**: Check resource quotas, node capacity, PVC binding

#### HPA Not Scaling

**Diagnosis:**
```bash
# Check HPA status
kubectl describe hpa <hpa-name> -n <namespace>

# Check Metrics Server
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system -l k8s-app=metrics-server

# Check resource requests
kubectl get rollout <rollout-name> -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Check current metrics
kubectl top pods -n <namespace>
```

**Solutions:**
- Ensure Metrics Server is running
- Verify resource requests are set in pod spec
- Check HPA min/max replicas are correct
- Verify target utilization percentage

#### Ingress Not Working

**Diagnosis:**
```bash
# Check Ingress resource
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# Check Ingress Controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Check service endpoints
kubectl get endpoints -n <namespace>
```

**Solutions:**
- Verify `ingress.className` matches Ingress Controller
- Check service selector matches pod labels
- Verify Ingress Controller is running
- Check LoadBalancer IP assignment (MetalLB)

#### ArgoCD Out of Sync

**Diagnosis:**
```bash
# Check application status
argocd app get <app-name>

# Check diff
argocd app diff <app-name>

# Check ignored differences
kubectl get application <app-name> -n argocd -o jsonpath='{.spec.ignoreDifferences}'
```

**Solutions:**
- Verify `ignoreDifferences` is configured for HPA-managed Rollouts
- Check if manual changes were made (will be overridden)
- Force refresh: `argocd app get <app-name> --refresh`
- Manual sync: `argocd app sync <app-name>`

---

### Performance Tuning

#### Resource Optimization

**Check Current Resource Usage:**
```bash
# Check pod resource usage
kubectl top pods -n <namespace>

# Check node capacity
kubectl describe nodes

# Check resource requests vs limits
kubectl get rollout <rollout-name> -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

**Update Resources:**
```bash
# Update via Helm
helm upgrade <release-name> ./charts/amazon-watcher-stack \
  --namespace <namespace> \
  --set backend.resources.requests.cpu=1000m \
  --set backend.resources.requests.memory=2Gi \
  --set backend.resources.limits.cpu=2000m \
  --set backend.resources.limits.memory=4Gi
```

#### HPA Tuning

**Adjust Scaling Behavior:**
```yaml
autoscaling:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
      policies:
      - type: Percent
        value: 50  # Scale down max 50% at a time
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0  # Scale up immediately
      policies:
      - type: Percent
        value: 100  # Can double replicas
        periodSeconds: 60
      - type: Pods
        value: 4  # Or add 4 pods max
        periodSeconds: 60
```

#### Database Tuning

**PostgreSQL Configuration:**
```bash
# Check current database config
kubectl exec <release-name>-database-0 -n <namespace> -- \
  psql -U postgres -c "SHOW ALL;"

# Update shared_buffers, max_connections, etc. via ConfigMap
kubectl edit configmap <release-name>-database-config -n <namespace>
```

---

### Quick Reference Commands

```bash
# Application Status
kubectl get all -n <namespace> -l app.kubernetes.io/instance=<release-name>

# All Resources
kubectl get rollout,hpa,svc,ingress,pvc -n <namespace>

# Watch Resources
watch -n 2 'kubectl get pods,rollout,hpa -n <namespace>'

# Logs (all components)
kubectl logs -n <namespace> -l app.kubernetes.io/instance=<release-name> --tail=50

# Events (sorted by time)
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Resource Usage
kubectl top pods -n <namespace> --sort-by=memory
kubectl top pods -n <namespace> --sort-by=cpu

# ArgoCD Quick Commands
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
argocd app rollback <app-name> <revision>
```

---

## Additional Resources

- [Kubernetes Infrastructure Setup](kubernetes/README.md) - Infrastructure components (MetalLB, Ingress, Argo Rollouts)
- [Argo CD Setup Guide](docs/ZABBIX_ARGOCD_SETUP.md) - Detailed Argo CD installation and configuration
- [Changing Helm Values in Argo CD](docs/CHANGE_VALUES.md) - Guide for managing Helm values in Argo CD

---

**Repository Maintained By**: Maborak Technologies Inc.  
**Last Updated**: January 2026
