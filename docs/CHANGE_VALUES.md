# How to Change Helm Values in ArgoCD

After ArgoCD has deployed your Zabbix chart, you can change Helm values using several methods:

## Method 1: ArgoCD CLI (Quick Changes)

### View Current Parameters
```bash
argocd app get prod
# Or see just the parameters:
kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}' | jq .
```

### Add or Update a Parameter
```bash
# Set a single parameter
argocd app set prod --helm-set replicas.zabbixServer=5

# Set multiple parameters
argocd app set prod \
  --helm-set replicas.zabbixServer=5 \
  --helm-set replicas.zabbixUI=3 \
  --helm-set image.tag=7.0.0

# Set nested values (use dot notation)
argocd app set prod --helm-set storage.mariadb.size=20Gi

# Set array values (use brackets)
argocd app set prod --helm-set 'storage.mariadb.accessModes[0]=ReadWriteOnce'
```

### Remove a Parameter
```bash
# Remove a parameter (set it to empty or use --helm-unset)
argocd app set prod --helm-unset replicas.zabbixServer
```

### Sync After Changes
```bash
# Manual sync
argocd app sync prod

# Or if auto-sync is enabled, it will sync automatically
```

## Method 2: kubectl (Direct Edit)

### Edit the Application Resource
```bash
kubectl edit application prod -n argocd
```

Then modify the `spec.source.helm.parameters` section:
```yaml
spec:
  source:
    helm:
      parameters:
      - name: replicas.zabbixServer
        value: "5"
      - name: replicas.zabbixUI
        value: "3"
      - name: image.tag
        value: "7.0.0"
```

Save and exit. ArgoCD will detect the change and sync if auto-sync is enabled.

### Or Use kubectl patch
```bash
# Add/update a parameter
kubectl patch application prod -n argocd --type merge -p '{
  "spec": {
    "source": {
      "helm": {
        "parameters": [
          {"name": "replicas.zabbixServer", "value": "5"},
          {"name": "replicas.zabbixUI", "value": "3"}
        ]
      }
    }
  }
}'
```

## Method 3: ArgoCD UI (Web Interface)

1. Open ArgoCD UI: `http://localhost:8080` (or your ArgoCD URL)
2. Navigate to your application (`prod`)
3. Click on the application
4. Click "Edit" or "App Details" → "Edit"
5. Scroll to "Helm Parameters" section
6. Add/edit/remove parameters
7. Click "Save" or "Sync"

## Method 4: Git (Best Practice for GitOps)

This is the **recommended approach** for production:

1. Edit `charts/zabbix/values.yaml` in your Git repository
2. Commit and push the changes
3. ArgoCD will automatically detect the change (if auto-sync is enabled) or you can manually sync

```bash
# Edit values.yaml
vim charts/zabbix/values.yaml

# Commit and push
git add charts/zabbix/values.yaml
git commit -m "Update Zabbix server replicas to 5"
git push
```

## Method 5: Use values.yaml File (Not Currently Configured)

If you want to use a separate values file instead of parameters:

```bash
# Create a values file
cat > /tmp/zabbix-values.yaml <<EOF
replicas:
  zabbixServer: 5
  zabbixUI: 3
image:
  tag: "7.0.0"
EOF

# Set the values file path in the application
argocd app set prod --values /tmp/zabbix-values.yaml
```

Or add it to the Application spec:
```yaml
spec:
  source:
    helm:
      valueFiles:
      - values.yaml
      - values-prod.yaml  # Optional: override file
```

## Examples

### Change Server Replicas
```bash
argocd app set prod --helm-set replicas.zabbixServer=5
argocd app sync prod
```

### Change Image Tag
```bash
argocd app set prod --helm-set image.tag=7.0.0
argocd app sync prod
```

### Change Storage Size
```bash
argocd app set prod --helm-set storage.mariadb.size=50Gi
argocd app sync prod
```

### Change Database Password
```bash
argocd app set prod --helm-set db.password=newpassword123
argocd app sync prod
```

## Important Notes

1. **Auto-Sync**: Your application has `automated` sync enabled, so changes will be applied automatically after a short delay.

2. **Parameter Format**: Helm parameters use dot notation for nested values:
   - `replicas.zabbixServer` → `replicas: { zabbixServer: ... }`
   - `storage.mariadb.size` → `storage: { mariadb: { size: ... } }`

3. **Value Types**: All values are strings in ArgoCD parameters. Helm will convert them:
   - Numbers: `"5"` → `5`
   - Booleans: `"true"` → `true`
   - Strings: `"value"` → `"value"`

4. **Current Parameters**: Your application currently has:
   - `replicas.zabbixServer=3`
   - `replicas.zabbixUI=5`

5. **View All Available Values**: Check `charts/zabbix/values.yaml` to see all configurable options.

## Troubleshooting

### Check if changes were applied
```bash
# View the application spec
kubectl get application prod -n argocd -o yaml

# View the rendered Helm values
argocd app manifests prod | grep -A 10 "replicas"
```

### Rollback changes
```bash
# View history
argocd app history prod

# Rollback to previous revision
argocd app rollback prod <revision-id>
```

### Check sync status
```bash
argocd app get prod
argocd app sync prod --dry-run  # Preview changes
```

