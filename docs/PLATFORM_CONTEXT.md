# Platform Context: Kubernetes GitOps Repository

## Repo Purpose and Current Scope
- Centralized source of truth for Kubernetes application deployments.
- Provides production-ready, security-hardened Helm charts.
- **Current Scope**:
  - `amazon-watcher-stack`: Microservices-based product monitoring system (Backend, UI, Screenshot service, PostgreSQL).
  - `zabbix`: Enterprise monitoring solution (Server, Web UI, MariaDB).

## GitOps Model
- **Primary Tool**: Argo CD.
- **Model**: Single `Application` per environment (dev, staging, production).
- **Source of Truth**: This Git repository.
- **Reconciliation**: Continuous sync between Git state and cluster state.
- **Finalizers**: Uses `resources-finalizer.argocd.argoproj.io` for clean deletions.

## Helm Strategy
- **Layout**: Mono-repo structure with all charts located in the `charts/` directory.
- **Chart Type**: Application charts (v2).
- **Values Strategy**:
  - `values.yaml`: Base default configuration with secure defaults.
  - Environment Overlays: Specific values files (e.g., `values-production.yaml`) or Argo CD parameters.
  - No current use of shared library charts; each chart is self-contained.
- **Rendering**: Templates are rendered client-side by Argo CD using the `helm` tool.

## Environment Model
- **Separation**: Logical isolation via Kubernetes namespaces.
- **Namespace Strategy**: 
  - `dev`: Development and testing.
  - `staging`: Pre-production validation.
  - `production`: Live traffic.
  - `automated`: Dedicated namespace for automated deployments via scripts.
- **Cluster Targeting**: Primarily targets the `in-cluster` destination (`https://kubernetes.default.svc`).

## Deployment Workflows
- **Local Deployment**: Supported via standard Helm CLI (`helm install/upgrade`).
- **Argo CD Trigger**: Triggered by Git commits (polling or webhooks).
- **Sync Management**:
  - **Automated Sync**: Enabled by default in production-grade manifests.
  - **Prune**: Automatically deletes resources removed from Git.
  - **Self-Heal**: Automatically reverts manual cluster changes to match Git state.

## Core Conventions
- **Naming**: 
  - Resource names follow `<chart-name>-<release-name>` pattern using Helm helpers.
  - PascalCase required for certain cluster-scoped resource kinds in Argo CD projects (e.g., `PersistentVolume`).
- **Labels/Annotations**: Standard `app.kubernetes.io` labels for ownership and versioning.
- **Versioning**: Semantic Versioning (SemVer) for charts; stable tagging for container images.

## Operational Capabilities
- **Health Checks**: Liveness and readiness probes configured for all application components.
- **Resource Management**: Explicit CPU/Memory requests and limits defined for all containers.
- **Autoscaling**: Horizontal Pod Autoscalers (HPA) implemented for stateless services (UI, Backend, Screenshot).
- **Deployment Strategy**: 
  - **Argo Rollouts**: Used for canary and blue-green deployments (Backend, UI).
  - **PDBs**: Pod Disruption Budgets for high availability during maintenance.
- **Ingress/Gateway**: 
  - NGINX Ingress Controller for external access.
  - Istio Service Mesh integration (VirtualService, DestinationRule, Telemetry) optional.
  - MetalLB support for LoadBalancer services in bare-metal/local clusters.

## Security Posture
- **RBAC**: 
  - Dedicated `ServiceAccount` per component.
  - Least-privilege `Role` and `RoleBinding` configurations.
- **Workload Security**:
  - `runAsNonRoot`: True (configured in many contexts).
  - `allowPrivilegeEscalation`: False.
  - `PodSecurityPolicy` / `securityContext` conventions enforced.
- **Secrets Handling**:
  - Stored as native Kubernetes `Secret` objects.
  - Never stored in plain text within `values.yaml` or Git.
  - Integration support for External Secrets or Sealed Secrets.
- **Network Isolation**: `NetworkPolicy` resources implementing default-deny with explicit ingress/egress rules.

## Observability
- **Metrics**: Prometheus metrics endpoints exposed by applications.
- **Logging**: Structured logging for backend services.
- **Tracing**: Istio/OpenTelemetry potential (hooks present in templates).

## Known Constraints and Limitations
- **Kubernetes Version**: Requires 1.24+ for full feature compatibility.
- **CRDs**: Requires `rollouts.argoproj.io` CRDs for charts using Argo Rollouts.
- **CNI**: NetworkPolicies require a CNI that supports them (e.g., Calico, Cilium).
- **Storage**: Persistent storage requires pre-configured `StorageClass` (defaults often to `standard` or `local-path`).
- **Argo CD Config**: Requires `controller.applicationNamespaces=""` to manage cluster-scoped resources like `PersistentVolume`.
