# Current State - Kubernetes GitOps

### Last Completed
- Unified rollout history management via `global.revisionHistoryLimit`.
- Enhanced database StatefulSet with `pvcRetentionPolicy` and `subPath` support.
- Refined HPA conditional logic for more robust template rendering.
- Fixed NetworkPolicy egress for DNS resolution.

### In Progress
- Reviewing documentation consistency across context files.
- Refactoring `amazon-watcher-backend-argocd.sh` for improved session handling.

### Next Planned
- Implement automated secret rotation for backend JWT.
- Verify multi-namespace isolation using NetworkPolicies.
- Optimize ResourceQuotas for the `dev` environment.

### Constraints
- `pvcRetentionPolicy` requires Kubernetes 1.27+ or specific feature gates.
- Metrics Server on Docker Desktop requires TLS skip configuration.
- MetalLB relies on Layer 2 advertisement; requires host-accessible IP pool.
- Argo CD sync policies require explicit `AllowEmpty` or `IgnoreDifferences` for certain Rollout behaviors.
