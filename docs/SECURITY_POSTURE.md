# Security Posture

## Secret Management
- **Approach**: Native Kubernetes `Secret` resources.
- **Git Safety**: Secrets are NEVER stored in `values.yaml` or Git manifests.
- **Injection**: Secrets are mounted as environment variables or files into pods.
- **Threat Boundary**: Secret access is controlled via namespace-scoped RBAC.
- **Automation**: JWT secrets are generated via one-time Kubernetes `Jobs` (`backend-jwt-gen-job.yaml`).

## RBAC / Least Privilege
- **ServiceAccounts**: Every component (Backend, UI, Database) has its own dedicated `ServiceAccount`.
- **RBAC Roles**:
  - Roles define granular permissions (e.g., `get`, `list` on `secrets`).
  - No use of the `default` ServiceAccount for application logic.
- **Namespace Isolation**: Permissions are predominantly namespace-scoped using `Role` and `RoleBinding`.

## Workload Security
- **SecurityContext**:
  - Many containers specify `runAsNonRoot: true` and `allowPrivilegeEscalation: false`.
  - Pods use standard security contexts to drop unnecessary Linux capabilities.
- **Image Security**:
  - Pull policies default to `IfNotPresent` or `Always`.
  - Recommendation for production: Pin images by digest.

## Network Policy Usage
- **Principles**: Default-deny posture.
- **Implementation**:
  - `NetworkPolicy` resources are defined for UI, Backend, Screenshot service, and Database.
  - **Rules**:
    - UI: Only allows ingress from the Ingress Controller.
    - Backend: Only allows ingress from UI pods.
    - Database: Only allows ingress from Backend or CLI/CronJob pods.
    - Egress: Restricted to required external service endpoints and DNS (using canonical `kubernetes.io/metadata.name: kube-system` labels).

## Admission Controls and Policies
- **Argo CD Project Restrictions**:
  - Projects restrict which resource kinds can be deployed (Whitelist approach).
  - Explicit allowance required for cluster-scoped resources like `PersistentVolume`.
- **Namespace Hardening**: Namespaces are used as hard security boundaries for GitOps reconciliation.

## Compliance and Audit
- **Audit Logs**: Relies on standard Kubernetes API server auditing.
- **State Reconciliation**: Argo CD `self-heal` ensures that unauthorized manual changes to resources are automatically reverted, maintaining the security baseline defined in Git.
