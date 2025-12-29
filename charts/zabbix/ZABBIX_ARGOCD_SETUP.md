# Zabbix with ArgoCD Setup Guide

This guide documents the complete process of setting up Zabbix using ArgoCD, including all the non-obvious configuration steps and troubleshooting.

## Prerequisites

- Kubernetes cluster (tested with Docker Desktop Kubernetes)
- Helm installed
- ArgoCD CLI installed (`argocd` command)
- SSH key for accessing private GitHub repositories
- Docker installed (for pulling images locally if needed)

## Step 1: Install ArgoCD

### 1.1 Create Namespace

```bash
kubectl create namespace argocd
```

### 1.2 Install ArgoCD with Proper Configuration

**Important:** ArgoCD must be installed with `controller.applicationNamespaces=""` to allow cluster-scoped resources like PersistentVolumes.

```bash
helm install argocd argo/argo-cd -n argocd \
  --set server.service.type=LoadBalancer \
  --set controller.applicationNamespaces=""
```

**Why this matters:** Without this setting, ArgoCD runs in "namespaced mode" and cannot manage cluster-scoped resources like PersistentVolumes, which Zabbix requires.

### 1.3 Wait for ArgoCD to be Ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
```

### 1.4 Set Up Port Forwarding

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 1.5 Get Admin Password and Login

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Login to ArgoCD CLI
argocd login localhost:8080 --insecure --username admin --password <PASSWORD>
```

## Step 2: Create and Configure ArgoCD Project

Create the project and immediately configure it to allow cluster-scoped resources (PersistentVolumes):

```bash
# Create the project
argocd proj create zabbix --description "Zabbix project"

# Allow PersistentVolumes (cluster-scoped resource required by Zabbix)
argocd proj allow-cluster-resource zabbix "" persistentvolumes
```

**Why this is critical:** Zabbix requires PersistentVolumes, which are cluster-scoped resources. ArgoCD projects must explicitly allow cluster-scoped resources, otherwise you'll get errors like:
```
cluster level PersistentVolume "zabbixprod-mariadb-pv" can not be managed when in namespaced mode
```

Verify the configuration:
```bash
argocd proj get zabbix
```

You should see:
```
Allowed Cluster Resources:   /persistentvolumes
```

### 2.2 Add Repository to Project

```bash
argocd proj add-source zabbix git@github.com:Maborak-Technologies-Inc/helm.git
```

### 2.3 Add Destination Namespace

```bash
argocd proj add-destination zabbix https://kubernetes.default.svc automated
```

## Step 3: Add Repository to ArgoCD

Add the private GitHub repository with SSH key:

```bash
argocd repo add git@github.com:Maborak-Technologies-Inc/helm.git \
  --ssh-private-key-path ~/.ssh/id_rsa_argocd
```

**Note:** The `--ssh-private-key-path` flag automatically handles SSH key configuration for ArgoCD.

Verify repository is accessible:
```bash
argocd repo list
```

You should see the repository with status "Successful".

## Step 4: Create Target Namespace

```bash
kubectl create namespace automated
```

## Step 5: Create ArgoCD Application

**Important:** Before creating the application, ensure your Helm chart's PV and PVC templates use the same `storageClassName`. If your chart has a mismatch, fix it in the chart templates (see Issue 1 in Troubleshooting) or use Helm values to override.

Create the ArgoCD application:

```bash
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix
```

**Alternative:** If you need to override Helm values (e.g., to set storageClassName), you can create the application with a values file or use the `--helm-set` flag:

```bash
# Using Helm values file
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --helm-set storage.mariadb.storageClassName=standard

# Or create a values file and reference it
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --values values-override.yaml
```

## Step 6: Sync Application

```bash
argocd app sync prod
```

## Step 7: Troubleshooting Common Issues

### Issue 1: PersistentVolume Not Binding

**Symptom:** PVC shows as "Pending" even though PV exists.

**Cause:** Storage class mismatch between PV and PVC. The Helm chart's PV template may conditionally set a storage class (e.g., `local-path`) while the PVC defaults to `standard`, or vice versa.

**Why it works on on-premise but not Docker Desktop:**
- **Docker Desktop for Mac:** Has `standard` set as the **default storage class**. When a PVC doesn't specify `storageClassName`, Kubernetes automatically assigns the default (`standard`). If your PV is created without a storage class (or with an empty string), it cannot bind to a PVC that has `storageClassName: standard`.
- **On-premise Kubernetes:** May not have a default storage class configured. In this case, both PV and PVC end up with no storage class (empty string), so they can bind successfully.

**The mismatch occurs because:**
1. PV is created without `storageClassName` (or with empty string `""`)
2. PVC is created without explicit `storageClassName`
3. Docker Desktop automatically assigns `standard` to the PVC (because it's the default)
4. PV (`""`) ≠ PVC (`standard`) → **Binding fails**
5. On-premise: PV (`""`) = PVC (`""`) → **Binding succeeds**

**Prevention:** Fix this in your Helm chart by ensuring both PV and PVC templates use the same `storageClassName` logic.

**Current PV template logic:**
```yaml
spec:
  {{- if .Values.storage.storageClass }}
  storageClassName: {{ .Values.storage.storageClass }}
  {{- else if (lookup "storage.k8s.io/v1" "StorageClass" "" "local-path") }}
  storageClassName: local-path
  {{- end }}
  # ... rest of spec
```

**Problem:** The PVC template likely doesn't have the same conditional logic, so it defaults to the cluster's default storage class (`standard` on Docker Desktop).

**Solution 1: Set storageClass in values.yaml (Recommended)**

Add to your `values.yaml`:
```yaml
storage:
  storageClass: "standard"  # or "local-path" or "" for no storage class
  mariadb:
    size: "5Gi"
    # ... other values
```

This ensures both PV and PVC use the same storage class.

**Solution 2: Update PVC template to match PV logic**

Update `templates/pvc-mariadb.yaml` to use the same conditional logic:
```yaml
spec:
  {{- if .Values.storage.storageClass }}
  storageClassName: {{ .Values.storage.storageClass }}
  {{- else if (lookup "storage.k8s.io/v1" "StorageClass" "" "local-path") }}
  storageClassName: local-path
  {{- end }}
  accessModes:
    - {{ .Values.storage.mariadb.accessModes | first }}
  resources:
    requests:
      storage: {{ .Values.storage.mariadb.size }}
```

**Solution 3: Use Helm values when creating ArgoCD app**

When creating the application, override the storage class:
```bash
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --helm-set storage.storageClass=standard
```

**Workaround (if chart can't be fixed immediately):**

1. Check storage classes:
```bash
kubectl get storageclass
```

2. Update PV to match PVC's storage class:
```bash
kubectl patch pv zabbixprod-mariadb-pv -p '{"spec":{"storageClassName":"standard"}}'
```

3. Delete and recreate PVC:
```bash
kubectl delete pvc zabbixprod-mariadb-pvc -n automated
argocd app sync prod
```

**Note:** This is a temporary workaround. The proper fix is to update the Helm chart templates as shown above.

### Issue 2: Alpine Image Pull Failures

**Symptom:** Pods stuck in `Init:ImagePullBackOff` or `Init:ErrImagePull` with error:
```
Failed to pull image "alpine": failed to pull and unpack image "docker.io/library/alpine:latest": failed to read expected number of bytes: unexpected EOF
```

**Cause:** Network connectivity issues from cluster nodes to Docker Hub.

**Solution:** Pull images locally with Docker (Docker Desktop shares images with Kubernetes):

```bash
# Pull the required images
docker pull alpine:latest
docker pull alpine:3.19  # if using specific version
docker pull busybox:1.36  # alternative lightweight image

# Delete the failing pod to trigger a new pull
kubectl delete pod <pod-name> -n automated
```

The images will be available to the cluster after being pulled locally.

### Issue 3: ArgoCD in Namespaced Mode Error

**Symptom:** Error message:
```
cluster level PersistentVolume "zabbixprod-mariadb-pv" can not be managed when in namespaced mode
```

**Cause:** ArgoCD was installed without proper configuration for cluster-scoped resources.

**Solution:** Reinstall ArgoCD with the correct configuration (see Step 1.2), or ensure the ConfigMap doesn't have `application.namespaces` set:

```bash
# Check if the key exists
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep "application.namespaces"

# If it exists, remove it
kubectl patch configmap argocd-cmd-params-cm -n argocd --type json \
  -p='[{"op": "remove", "path": "/data/application.namespaces"}]'

# Restart the controller
kubectl rollout restart statefulset argocd-application-controller -n argocd
```

### Issue 4: Repository Not Accessible

**Symptom:** Error when adding repository:
```
SSH agent requested but SSH_AUTH_SOCK not-specified
```

**Solution:** Use the `--ssh-private-key-path` flag when adding the repository (see Step 3).

## Step 8: Verify Deployment

### Check Application Status

```bash
argocd app get prod
```

Expected output:
- Sync Status: `Synced`
- Health Status: `Healthy` (or `Progressing` during initial deployment)

### Check Pods

```bash
kubectl get pods -n automated
```

All pods should show `Running` and `READY`:
```
NAME                                  READY   STATUS    RESTARTS   AGE
zabbixprod-mariadb-xxx               1/1     Running   0          Xm
zabbixprod-server-xxx                2/2     Running   0          Xm
zabbixprod-ui-xxx                    1/1     Running   0          Xm
```

### Check Deployments

```bash
kubectl get deployments -n automated
```

All should show `1/1` Ready:
```
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
zabbixprod-mariadb   1/1     1            1           Xm
zabbixprod-server    1/1     1            1           Xm
zabbixprod-ui        1/1     1            1           Xm
```

## Step 9: Access Zabbix UI

### Option 1: Port Forward (Recommended)

```bash
kubectl port-forward svc/zabbixprod-ui -n automated 8081:80
```

Then access: `http://localhost:8081`

### Option 2: NodePort (if service is NodePort)

```bash
kubectl get svc zabbixprod-ui -n automated
# Use the NodePort number with any node IP
```

### Option 3: LoadBalancer (if service is LoadBalancer)

```bash
kubectl get svc zabbixprod-ui -n automated
# Use the EXTERNAL-IP
```

### Default Credentials

- Username: `Admin` (case-sensitive)
- Password: `zabbix`

(Check your Helm values or ConfigMap for custom credentials)

## Step 10: Access ArgoCD UI

ArgoCD UI is already port-forwarded on port 8080:

- URL: `https://localhost:8080`
- Username: `admin`
- Password: (from Step 1.5)

## Key Configuration Points Summary

1. **ArgoCD Installation:** Must use `controller.applicationNamespaces=""` to allow cluster-scoped resources
2. **Project Configuration:** Must explicitly allow PersistentVolumes as cluster resources
3. **SSH Keys:** Required for private repositories, must be configured as a secret
4. **Storage Classes:** PV and PVC must have matching storage classes
5. **Image Pulls:** May need to pull images locally if cluster nodes have network issues

## Common Commands Reference

```bash
# Check ArgoCD application status
argocd app get prod

# Sync application
argocd app sync prod

# Check pods
kubectl get pods -n automated

# Check services
kubectl get svc -n automated

# Check persistent volumes
kubectl get pv
kubectl get pvc -n automated

# View ArgoCD logs
kubectl logs -n argocd argocd-application-controller-0

# Port forward Zabbix UI
kubectl port-forward svc/zabbixprod-ui -n automated 8081:80

# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Troubleshooting Checklist

- [ ] ArgoCD installed with `controller.applicationNamespaces=""`
- [ ] Project allows PersistentVolumes as cluster resource
- [ ] Repository added and accessible (check `argocd repo list`)
- [ ] Target namespace exists
- [ ] PV and PVC have matching storage classes
- [ ] Images pulled locally if cluster has network issues
- [ ] All pods in Running state
- [ ] Application shows as Synced and Healthy in ArgoCD

## Notes

- The `alpine` image pull issue is common in Docker Desktop Kubernetes due to network connectivity from cluster nodes to Docker Hub
- PersistentVolume binding issues often stem from storage class mismatches
- ArgoCD's namespaced mode is a security feature that restricts cluster-scoped resource management
- Always verify the project configuration includes cluster resource permissions before syncing

