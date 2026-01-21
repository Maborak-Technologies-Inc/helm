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

## Additional Resources

- [Kubernetes Infrastructure Setup](kubernetes/README.md) - Infrastructure components (MetalLB, Ingress, Argo Rollouts)
- [Argo CD Setup Guide](docs/ZABBIX_ARGOCD_SETUP.md) - Detailed Argo CD installation and configuration
- [Changing Helm Values in Argo CD](docs/CHANGE_VALUES.md) - Guide for managing Helm values in Argo CD

---

**Repository Maintained By**: Maborak Technologies Inc.  
**Last Updated**: January 2026
