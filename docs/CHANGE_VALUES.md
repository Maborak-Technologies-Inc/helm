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

**⚠️ Important:** ArgoCD CLI does **NOT** have a `--helm-unset` or `--helm-remove` flag. You cannot remove Helm parameters using `argocd app set`.

To remove Helm parameters, you **must** use `kubectl` to edit the Application resource directly (see Method 2 below).

```bash
# Check current parameters
kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}' | jq .

# To remove parameters, edit the application (see Method 2: kubectl)
kubectl edit application prod -n argocd
# Then remove or comment out the parameters you want to remove
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

**To add/update parameters:**
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

**To remove all parameters** (so values.yaml from Git is used):
```yaml
spec:
  source:
    helm:
      # parameters:  # Comment out or remove this entire section
      # - name: replicas.zabbixServer
      #   value: "5"
```

**To remove specific parameters**, just delete the lines you don't want:
```yaml
spec:
  source:
    helm:
      parameters:
      # - name: replicas.zabbixServer  # Removed this one
      #   value: "5"
      - name: replicas.zabbixUI
        value: "3"
```

Save and exit. ArgoCD will detect the change and sync if auto-sync is enabled.

### Or Use kubectl patch

**Add/update parameters:**
```bash
# Add/update parameters
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

**Remove all parameters** (to use values.yaml from Git):
```bash
# Remove all Helm parameters in one command
kubectl patch application prod -n argocd --type json -p='[
  {"op": "remove", "path": "/spec/source/helm/parameters"}
]'
```

This will remove all Helm parameters and ArgoCD will use `values.yaml` from your Git repository.

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

4. **View All Available Values**: Check `charts/zabbix/values.yaml` to see all configurable options.

## ⚠️ CRITICAL: Helm Parameters Override values.yaml

**Important:** Helm parameters set via `argocd app set` or in the Application spec **OVERRIDE** values from `values.yaml` in your Git repository.

### The Problem

If you have Helm parameters configured in ArgoCD:
```yaml
spec:
  source:
    helm:
      parameters:
      - name: replicas.zabbixServer
        value: "5"
```

And you update `values.yaml` in GitHub:
```yaml
replicas:
  zabbixServer: 1
```

**The parameters will take precedence**, and your Git changes will NOT be applied!

### How to Check

```bash
# Check if you have Helm parameters overriding values.yaml
kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}' | jq .

# Compare with values.yaml in Git
cat charts/zabbix/values.yaml | grep -A 5 "replicas:"
```

### Solution: Remove Parameters to Use values.yaml

To use `values.yaml` from Git instead of parameters, you need to **remove the Helm parameters**:

#### Option 1: Using kubectl (Recommended)

```bash
# Edit the application and remove the helm.parameters section
kubectl edit application prod -n argocd
```

Then remove or comment out the `parameters:` section:
```yaml
spec:
  source:
    helm:
      # parameters:  # Remove or comment this out
      # - name: replicas.zabbixServer
      #   value: "5"
```

#### Option 2: Using kubectl patch (Remove all parameters) ⚡ Quick Method

**This is the fastest way to remove all parameters:**

```bash
# Remove all Helm parameters in one command
kubectl patch application prod -n argocd --type json -p='[
  {"op": "remove", "path": "/spec/source/helm/parameters"}
]'
```

**Verify it worked:**
```bash
# Check that parameters are removed
kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}' | jq .
# Should return nothing or null

# ArgoCD will auto-sync and use values.yaml from Git
```

#### Option 3: Using kubectl patch (Remove specific parameters)

```bash
# Get current parameters
CURRENT_PARAMS=$(kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}')

# Create new parameters array without the ones you want to remove
# Example: Remove replicas.zabbixServer but keep others
kubectl patch application prod -n argocd --type merge -p '{
  "spec": {
    "source": {
      "helm": {
        "parameters": [
          {"name": "replicas.zabbixUI", "value": "2"}
        ]
      }
    }
  }
}'
```

### After Removing Parameters

Once parameters are removed, ArgoCD will use `values.yaml` from your Git repository:

1. **Commit and push** your `values.yaml` changes to Git
2. ArgoCD will automatically sync (if auto-sync is enabled)
3. Or manually sync: `argocd app sync prod`

### Best Practice

- **For GitOps**: Use `values.yaml` in Git, avoid Helm parameters
- **For quick testing**: Use Helm parameters temporarily, then remove them
- **For environment-specific configs**: Use separate values files (e.g., `values-prod.yaml`, `values-staging.yaml`)

## Troubleshooting

### Why aren't my Git changes being applied?

**Symptom:** You updated `values.yaml` in GitHub, but ArgoCD isn't using the new values.

**Cause:** Helm parameters in ArgoCD are overriding `values.yaml`.

**Solution:**
```bash
# 1. Check if you have Helm parameters
kubectl get application prod -n argocd -o jsonpath='{.spec.source.helm.parameters}' | jq .

# 2. If parameters exist, remove them (see "CRITICAL: Helm Parameters Override values.yaml" section above)
kubectl edit application prod -n argocd
# Remove the parameters: section

# 3. Force sync to use values.yaml from Git
argocd app sync prod
```

### Check if changes were applied
```bash
# View the application spec
kubectl get application prod -n argocd -o yaml

# View the rendered Helm values
argocd app manifests prod | grep -A 10 "replicas"

# Compare deployed vs configured
echo "Deployed replicas:" && kubectl get deployment zabbixprod-server -n automated -o jsonpath='{.spec.replicas}' && echo "" && echo "values.yaml:" && cat charts/zabbix/values.yaml | grep -A 3 "replicas:"
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

