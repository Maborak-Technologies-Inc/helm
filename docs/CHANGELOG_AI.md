# AI-Driven Changelog (GitOps)

## [2026-01-29] - Global Rollout Defaults and Database Persistence Policies
### Summary
Implemented global configuration for rollout history retention and enhanced database persistence options, including PVC retention policies and volume subpath support. Refined HPA conditional logic.

### Files Modified
- `charts/amazon-watcher-stack/values.yaml`: Added `global.revisionHistoryLimit` and database storage enhancements.
- `charts/amazon-watcher-stack/templates/database-statefulset.yaml`: Integrated `pvcRetentionPolicy` and `subPath`.
- `charts/amazon-watcher-stack/templates/maborak-deployment.yaml`: Migrated to global `revisionHistoryLimit`.
- `charts/amazon-watcher-stack/templates/screenshot-rollout.yaml`: Migrated to global `revisionHistoryLimit` and updated HPA check.
- `charts/amazon-watcher-stack/templates/ui-rollout.yaml`: Migrated to global `revisionHistoryLimit` and updated HPA check.

### Deployment Impact
- **StatefulSet Management**: Database PVCs can now be automatically deleted when the StatefulSet is removed or scaled down if `pvcRetentionPolicy` is set (requires K8s 1.27+).
- **Rollout History**: Standardized on 10 revisions globally, reducing cluster metadata overhead for old ReplicaSets.

### GitOps Impact
- **Consistency**: Argo CD now reconciles a unified `revisionHistoryLimit` across all components via global defaults.

### Helm Impact
- **Global Defaults**: Introduced `global.revisionHistoryLimit` to reduce boilerplate across service values.
- **Persistence Flexibility**: Added `subPath` support for database volume mounts.

### Security Impact
- No significant changes to RBAC or isolation.

### Notes/Follow-ups
- Ensure target clusters are running K8s 1.27+ for `pvcRetentionPolicy` features.

## [2026-01-28] - Fixed NetworkPolicy and Platform Config
### Summary
Fixed labeling issues for DNS resolution in NetworkPolicy, updated MetalLB address pool, and added Argo CD resource management automation. Initial platform documentation was also established.

### Files Modified
- `charts/amazon-watcher-stack/templates/maborak-networkpolicy.yaml`: Updated `kube-system` namespace selector for DNS.
- `docs/amazon-watcher-backend-argocd.sh`: Improved Argo CD access check and removed port-forwarding logic.
- `kubernetes/README.md`: Updated Metrics Server TLS fix documentation.
- `kubernetes/metallb-config.yaml`: Updated MetalLB `IPAddressPool` to use `192.168.0.200/32`.
- `scripts/disable_argocd_resources.sh`: [NEW] Automation script to scale/suspend Argo CD application resources.
- `docs/ARGOCD_CONTEXT.md`, `docs/CHART_CATALOG.md`, `docs/PLATFORM_CONTEXT.md`, `docs/SECURITY_POSTURE.md`: [NEW] Initial platform context documentation.

### Deployment Impact
- **DNS Resolution**: Fixed egress rules to `kube-system` DNS by using canonical labels (`kubernetes.io/metadata.name`), improving reliability across different Kubernetes distributions.
- **MetalLB**: LoadBalancer IP pool consolidated to a single dedicated IP (`192.168.0.200`).

### GitOps Impact
- **Automation**: New `disable_argocd_resources.sh` allows for rapid scaling of all application components to zero for maintenance or cost-saving.
- **Scripting**: `amazon-watcher-backend-argocd.sh` now relies on pre-authenticated session rather than attempting to manage port-forwards and credentials internally.

### Helm Impact
- **NetworkPolicy**: Corrected selector logic for DNS access in `amazon-watcher-stack` chart.

### Security Impact
- **RBAC/Isolation**: NetworkPolicy egress tightened to specific Canonical DNS labels. No changes to cluster-level RBAC.

### Notes/Follow-ups
- Baseline documentation established for AI-assisted repository maintenance.
