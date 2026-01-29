# Current State - Kubernetes GitOps

### Last Completed
- Initial platform context documentation (`PLATFORM_CONTEXT.md`, `CHART_CATALOG.md`, `ARGOCD_CONTEXT.md`, `SECURITY_POSTURE.md`).
- Fixed NetworkPolicy egress label mismatch for DNS resolution in `amazon-watcher-stack`.
- Updated MetalLB configuration for single-IP load balancer pool.
- Implemented `scripts/disable_argocd_resources.sh` for Argo CD application management.

### In Progress
- Refactoring `amazon-watcher-backend-argocd.sh` for improved session handling.
- Reviewing ingress configurations for external access consistency.

### Next Planned
- Implement automated secret rotation for backend JWT.
- Verify multi-namespace isolation using NetworkPolicies.
- Optimize ResourceQuotas for the `dev` environment.

### Constraints
- Metrics Server on Docker Desktop requires TLS skip configuration.
- MetalLB relies on Layer 2 advertisement; requires host-accessible IP pool.
- Argo CD sync policies require explicit `AllowEmpty` or `IgnoreDifferences` for certain Rollout behaviors.
