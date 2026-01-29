# Argo CD Context

## Manifest Locations
- **Application Templates**: `docs/argocd-application-template.yaml`.
- **Setup Scripts**: `docs/setup-argocd.sh`, `docs/zabbix-argocd.sh`, `docs/amazon-watcher-backend-argocd.sh`.

## Argo CD Objects Used
- **Application**: The primary unit of deployment, mapping a Git path to a cluster namespace.
- **AppProject**: Used to group applications and restrict resource access (e.g., `zabbix` project).
- **ApplicationSet**: Not explicitly used in the current implementation, but standard `Application` objects are manually or script-generated.

## Source of Truth Structure
- **Global Repository**: `git@github.com:Maborak-Technologies-Inc/helm.git`.
- **Environment Mapping**:
  - `dev`: `path: charts/<chart-name>`, `namespace: dev`.
  - `staging`: `path: charts/<chart-name>`, `namespace: staging`.
  - `production`: `path: charts/<chart-name>`, `namespace: production`.

## Sync Policies
- **Automated Sync**: Enabled (`automated: {}`).
- **Prune**: Enabled (`prune: true`) to ensure resources are deleted when removed from Git.
- **Self-Heal**: Enabled (`selfHeal: true`) to prevent configuration drift from manual changes.
- **CreateNamespace**: Enabled (`CreateNamespace=true`) to automate environment setup.
- **IgnoreDifferences**: Configured for `Rollout` objects to ignore `spec/replicas` when managed by HPA.

## How to Add a New App/Chart to Argo CD
1. **Prepare the Chart**: Ensure the chart is in the `charts/` directory and follows naming conventions.
2. **Create/Update AppProject**:
   ```bash
   argocd proj create <project-name>
   argocd proj allow-cluster-resource <project-name> "" PersistentVolume
   ```
3. **Deploy the Application**:
   - Use the template `docs/argocd-application-template.yaml`.
   - Update `metadata.name`, `spec.source.path`, and `spec.destination.namespace`.
   - Apply the manifest: `kubectl apply -f my-app.yaml`.
4. **Alternative (Scripted)**:
   - Use automation scripts like `./docs/zabbix-argocd.sh install --app <name>`.

## Operational Utilities
- `scripts/disable_argocd_resources.sh`: Scale all workloads (Deployments, StatefulSets, Rollouts) to 0 or suspend CronJobs for a specific Argo CD application.
- `docs/setup-argocd.sh`: Automated bootstrap of the Argo CD server itself.
- `docs/amazon-watcher-backend-argocd.sh`: Deployment script using pre-authenticated session (managed via `argocd login`).
