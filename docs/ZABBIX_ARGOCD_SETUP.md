# Zabbix with ArgoCD Setup Guide

This guide documents the complete process of setting up Zabbix using ArgoCD, including all the non-obvious configuration steps and troubleshooting.

## Prerequisites

- Kubernetes cluster (tested with Docker Desktop Kubernetes)
- Helm installed (see Part 1 below)
- ArgoCD CLI installed (see Part 1 below)
- SSH key for accessing private GitHub repositories (located at `~/.ssh/id_rsa_argocd`)
- Docker installed (for pulling images locally if needed)

---

## Part 1: Helm Setup

Helm is a package manager for Kubernetes that is required to install ArgoCD. Follow the instructions below for your operating system.

### Linux / WSL

**Using the official install script (recommended):**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Using package manager:**

```bash
# Ubuntu/Debian
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Fedora/RHEL/CentOS
sudo dnf install helm
```

### macOS

**Using Homebrew (recommended):**

```bash
brew install helm
```

**Using the official install script:**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows

**Using Chocolatey:**

```powershell
choco install kubernetes-helm
```

**Using Scoop:**

```powershell
scoop install helm
```

**Using the official install script (requires Git Bash or WSL):**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Verify Helm Installation

After installation, verify Helm is working correctly:

```bash
helm version
```

You should see output similar to:
```
version.BuildInfo{Version:"v3.x.x", GitCommit:"...", GitTreeState:"...", GoVersion:"..."}
```

---

## Part 2: ArgoCD Setup

### 2.1 Install ArgoCD CLI

The ArgoCD CLI (`argocd`) is required to interact with ArgoCD and manage applications. Follow the instructions below for your operating system.

#### Linux / WSL

**Using the official install script (recommended):**

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

**For ARM64:**

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
chmod +x /usr/local/bin/argocd
```

**Using package manager:**

```bash
# Ubuntu/Debian (using snap)
sudo snap install argocd

# Or download manually
VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

#### macOS

**Using Homebrew (recommended):**

```bash
brew install argocd
```

**Using the official install script:**

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-darwin-amd64
chmod +x /usr/local/bin/argocd
```

**For Apple Silicon (ARM64):**

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-darwin-arm64
chmod +x /usr/local/bin/argocd
```

#### Windows

**Using Chocolatey:**

```powershell
choco install argocd
```

**Using Scoop:**

```powershell
scoop install argocd
```

**Manual installation:**

1. Download the latest release from [ArgoCD releases](https://github.com/argoproj/argo-cd/releases/latest)
2. Extract `argocd-windows-amd64.exe` and rename it to `argocd.exe`
3. Add it to your PATH or place it in a directory that's already in your PATH

#### Verify ArgoCD CLI Installation

After installation, verify the ArgoCD CLI is working correctly:

```bash
argocd version --client
```

You should see output similar to:
```
argocd: v2.x.x+xxxxxxx
  BuildDate: 2024-xx-xxTxx:xx:xxZ
  GitCommit: xxxxxxx
  GitTreeState: clean
  GoVersion: go1.xx.x
  Compiler: gc
  Platform: linux/amd64
```

### 2.2 Install ArgoCD Server

#### 2.2.1 Add ArgoCD Helm Repository

Before installing ArgoCD, add the ArgoCD Helm repository:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

#### 2.2.2 Create Namespace

```bash
kubectl create namespace argocd
```

#### 2.2.3 Install ArgoCD with Proper Configuration

**Important:** ArgoCD must be installed with `controller.applicationNamespaces=""` to allow cluster-scoped resources like PersistentVolumes.

```bash
helm install argocd argo/argo-cd -n argocd \
  --set server.service.type=NodePort \
  --set controller.applicationNamespaces=""
```

**Why this matters:** Without this setting, ArgoCD runs in "namespaced mode" and cannot manage cluster-scoped resources like PersistentVolumes, which Zabbix requires.

**Note:** NodePort is used instead of LoadBalancer to avoid Docker Desktop automatically mapping the service to localhost:80/443. With NodePort, you can access ArgoCD via the node IP and the assigned NodePort (e.g., `https://<NODE-IP>:30443`).

#### 2.2.4 Wait for ArgoCD to be Ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
```

### 2.3 Set Up Access to ArgoCD Server

You have two options to access the ArgoCD server:

**Option 1: Using kubectl port-forward (Recommended for quick access)**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Keep this terminal session running. In another terminal, proceed to Step 2.4.

**Option 2: Using argocd proxy (Alternative method)**

The `argocd proxy` command creates a local proxy to the ArgoCD server using your kubeconfig:

```bash
argocd proxy --port 8080
```

This command will:
- Automatically connect to the ArgoCD server in the cluster using your kubeconfig
- Create a local proxy on port 8080
- Run in the foreground (keep this terminal session running)

Keep this terminal session running. In another terminal, proceed to Step 2.4 to login.

**Note:** `argocd proxy` uses your kubeconfig to connect to the cluster, so it doesn't require prior login. However, you still need to login (Step 2.4) to use ArgoCD CLI commands. After the first login, you can use `argocd proxy` for future sessions instead of port-forwarding.

### 2.4 Get Admin Password and Login

**Method 1: Login through localhost (port-forward or proxy)**

If you're using port-forward (Option 1) or `argocd proxy` (Option 2) from Step 2.3:

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Login to ArgoCD CLI through localhost
argocd login localhost:8080 --insecure --username admin --password <PASSWORD>
```

**Method 2: Login directly to the cluster (no port-forward needed)**

You can also login directly to the ArgoCD server in the cluster without port-forwarding:

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Login directly using the service name
argocd login argocd-server.argocd.svc.cluster.local --name argocd --username admin --password <PASSWORD>
```

**Note:** After successful login, you can use `argocd proxy` for future sessions instead of port-forwarding. The proxy will use your saved credentials.

### 2.5 Create and Configure ArgoCD Project

Create the project and immediately configure it to allow cluster-scoped resources (PersistentVolumes):

```bash
# Create the project
argocd proj create zabbix --description "Zabbix project"

# Allow PersistentVolume (cluster-scoped resource required by Zabbix)
argocd proj allow-cluster-resource zabbix "" PersistentVolume
```

**Important:** The resource name must be in PascalCase and **singular** (`PersistentVolume`), not plural (`PersistentVolumes`) or lowercase (`persistentvolumes`). Using the wrong format will cause errors like "resource :PersistentVolume is not permitted in project zabbix".

**Why this is critical:** Zabbix requires PersistentVolume resources (cluster-scoped). ArgoCD projects must explicitly allow cluster-scoped resources using the **singular** resource kind name, otherwise you'll get errors like:
```
cluster level PersistentVolume "zabbixprod-mariadb-pv" can not be managed when in namespaced mode
```

Verify the configuration:
```bash
argocd proj get zabbix
```

You should see:
```
Allowed Cluster Resources:   /PersistentVolume
```

**Note:** The command requires PascalCase and **singular** form (`PersistentVolume`), not plural (`PersistentVolumes`) or lowercase (`persistentvolumes`). The output will show the resource in the format it was added.

#### 2.5.1 Add Repository to Project

```bash
argocd proj add-source zabbix git@github.com:Maborak-Technologies-Inc/helm.git
```

#### 2.5.2 Add Destination Namespace

```bash
argocd proj add-destination zabbix https://kubernetes.default.svc automated
```

### 2.6 Add Repository to ArgoCD

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

---

## Part 3: Zabbix Installation

Once Helm and ArgoCD are set up and running, you can install Zabbix using either the automated script or manual commands.

### 3.1 Automated Installation (Recommended)

The easiest way to install Zabbix with ArgoCD is using the provided automation script:

#### Using the Automation Script

```bash
# Install with default values (app: prod, namespace: automated, project: zabbix)
./docs/zabbix-argocd.sh install

# Install with custom app name
./docs/zabbix-argocd.sh install --app staging

# Install with custom app name (alternative syntax with equals sign)
./docs/zabbix-argocd.sh install --app=staging

# Force recreate existing app/project
./docs/zabbix-argocd.sh install --app prod --force

# Override multiple defaults
./docs/zabbix-argocd.sh install \
  --app=production \
  --namespace=prod \
  --project=zabbix-prod \
  --repo=git@github.com:your-org/helm.git
```

**Script Features:**
- ✅ Automatic ArgoCD project setup
- ✅ Repository configuration
- ✅ Application creation with auto-sync enabled (automated, self-heal, auto-prune)
- ✅ Safety checks (won't delete existing resources without `--force`)
- ✅ Support for both `--flag value` and `--flag=value` syntax
- ✅ Default values for common settings

**Default Values:**
- App Name: `prod`
- Namespace: `automated`
- Project: `zabbix`
- Repository: `git@github.com:Maborak-Technologies-Inc/helm.git`
- Chart Path: `charts/zabbix`
- SSH Key: `~/.ssh/id_rsa_argocd`

**Important Notes:**
- The script will **not** delete existing apps/projects unless you use `--force`
- Port-forward commands are **not** started automatically - you'll need to run them manually (instructions shown at the end)
- Uninstall requires `--force` flag for safety: `./docs/zabbix-argocd.sh uninstall --force`
- Applications are created with auto-sync enabled by default

**Script Options:**

All options support both `--flag value` and `--flag=value` syntax:

- `--app NAME` - ArgoCD application name (default: `prod`)
- `--namespace NAME` - Target Kubernetes namespace (default: `automated`)
- `--project NAME` - ArgoCD project name (default: `zabbix`)
- `--repo URL` - Git repository URL (default: `git@github.com:Maborak-Technologies-Inc/helm.git`)
- `--chart-path PATH` - Helm chart path in repository (default: `charts/zabbix`)
- `--ssh-key PATH` - SSH key path for private repos (default: `~/.ssh/id_rsa_argocd`)
- `--force` - Delete and recreate existing resources (apps, projects)

**Note:** The script automatically enables auto-sync when creating applications:
- `--sync-policy automated` - Auto-syncs when Git changes are detected
- `--self-heal` - Automatically corrects drift
- `--auto-prune` - Automatically removes deleted resources

### 3.2 Manual Installation

For experienced users who prefer manual setup, follow these steps:

#### 3.2.1 Create Target Namespace

```bash
kubectl create namespace automated
```

#### 3.2.2 Create ArgoCD Application

**Important:** Before creating the application, ensure your Helm chart's PV and PVC templates use the same `storageClassName`. If your chart has a mismatch, fix it in the chart templates (see Troubleshooting) or use Helm values to override.

Create the ArgoCD application with auto-sync enabled:

```bash
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

**Auto-sync features:**
- `--sync-policy automated`: Automatically syncs when Git changes are detected
- `--self-heal`: Automatically corrects drift (reverts manual changes)
- `--auto-prune`: Automatically removes resources deleted from Git

**Alternative:** If you need to override Helm values (e.g., to set storageClassName), you can create the application with a values file or use the `--helm-set` flag (with auto-sync):

```bash
# Using Helm values file with auto-sync
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --helm-set storage.mariadb.storageClassName=standard

# Or create a values file and reference it
argocd app create prod \
  --repo git@github.com:Maborak-Technologies-Inc/helm.git \
  --path charts/zabbix \
  --dest-name in-cluster \
  --dest-namespace automated \
  --project zabbix \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --values values-override.yaml
```

#### 3.2.3 Initial Sync

```bash
argocd app sync prod
```

**Note:** If auto-sync is enabled, this initial sync is the only manual sync needed. Future Git changes will be automatically synced.

---

## Part 4: Access and Verification

### 4.1 Verify Deployment

#### Check Application Status

```bash
argocd app get prod
```

Expected output:
- Sync Status: `Synced`
- Health Status: `Healthy` (or `Progressing` during initial deployment)

#### Check Pods

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

#### Check Deployments

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

### 4.2 Access Zabbix UI

**Note:** If you used the automation script (`zabbix-argocd.sh`), access instructions are displayed at the end of the installation. The script does not automatically start port-forwards - you need to run them manually.

#### Option 1: Using kubectl proxy (Recommended - single command for all services)

```bash
# Start kubectl proxy in a separate terminal
kubectl proxy
```

Then access services via the proxy:

**Zabbix UI:**
- For app named "prod": `http://localhost:8001/api/v1/namespaces/automated/services/zabbixprod-ui:80/proxy/`
- For app named "staging": `http://localhost:8001/api/v1/namespaces/automated/services/zabbixstaging-ui:80/proxy/`
- For custom app name: `http://localhost:8001/api/v1/namespaces/<NAMESPACE>/services/zabbix<APP_NAME>-ui:80/proxy/`

**ArgoCD UI (via the same proxy):**
- `http://localhost:8001/api/v1/namespaces/argocd/services/argocd-server:443/proxy/`

**Important:** Keep the `kubectl proxy` command running in a separate terminal. Press Ctrl+C to stop it.

#### Option 2: Port Forward (Direct access)

```bash
# For app named "prod" (default)
kubectl port-forward svc/zabbixprod-ui -n automated 8081:80

# For app named "staging"
kubectl port-forward svc/zabbixstaging-ui -n automated 8081:80

# For custom app name, use: zabbix<APP_NAME>-ui
kubectl port-forward svc/zabbix<APP_NAME>-ui -n <NAMESPACE> 8081:80
```

Then access: `http://localhost:8081`

**Important:** Keep the port-forward command running in a separate terminal. Press Ctrl+C to stop it.

#### Option 3: NodePort (if service is NodePort)

```bash
kubectl get svc zabbixprod-ui -n automated
# Use the NodePort number with any node IP
```

#### Option 4: LoadBalancer (if service is LoadBalancer)

```bash
kubectl get svc zabbixprod-ui -n automated
# Use the EXTERNAL-IP
```

#### Default Credentials

- Username: `Admin` (case-sensitive)
- Password: `zabbix`

(Check your Helm values or ConfigMap for custom credentials)

### 4.3 Access ArgoCD UI

The ArgoCD UI is accessible through the connection method you set up in Part 2.3:

**If using port-forward or argocd proxy:**

- URL: `https://localhost:8080`
- Username: `admin`
- Password: (from Part 2.4)

**Note:** Make sure the port-forward or `argocd proxy` is still running in a terminal session. If you closed it, restart it using the commands from Part 2.3.

**If using NodePort service type:**

```bash
# Get the NodePort number
kubectl get svc argocd-server -n argocd
# Get a node IP
kubectl get nodes -o wide
```

- URL: `https://<NODE-IP>:<NODE-PORT>` (e.g., `https://172.18.0.2:30443`)
- Username: `admin`
- Password: (from Part 2.4)

**Note:** On Docker Desktop, you can also use `localhost` instead of the node IP (e.g., `https://localhost:30443`).

**If using kubectl proxy:**

- URL: `http://localhost:8001/api/v1/namespaces/argocd/services/argocd-server:443/proxy/`
- Username: `admin`
- Password: (from Part 2.4)

---

## Part 5: Troubleshooting

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
  --sync-policy automated \
  --self-heal \
  --auto-prune \
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

**Solution:** Reinstall ArgoCD with the correct configuration (see Part 2.2.3), or ensure the ConfigMap doesn't have `application.namespaces` set:

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

**Solution:** Use the `--ssh-private-key-path` flag when adding the repository (see Part 2.6).

### Issue 5: PersistentVolume Resource Not Permitted

**Symptom:** Error message:
```
resource :PersistentVolume is not permitted in project zabbix
```

**Cause:** The ArgoCD project was configured to allow `persistentvolumes` (lowercase) instead of `PersistentVolume` (PascalCase). Kubernetes resource kinds are case-sensitive.

**Solution:** Remove the incorrect entry and add the correct one:

```bash
# Remove incorrect entry (if exists)
argocd proj remove-cluster-resource zabbix "" persistentvolumes

# Add correct entry (PascalCase singular)
argocd proj allow-cluster-resource zabbix "" PersistentVolume
```

**Important:** The resource name must be in PascalCase and **singular** (`PersistentVolume`), not plural (`PersistentVolumes`) or lowercase (`persistentvolumes`).

---

## Part 6: Common Commands Reference

```bash
# Check ArgoCD application status
argocd app get prod

# Sync application (if auto-sync is not enabled)
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

# Using kubectl proxy (single command for all services)
kubectl proxy
# Then access: http://localhost:8001/api/v1/namespaces/automated/services/zabbixprod-ui:80/proxy/

# Port forward Zabbix UI (direct access)
kubectl port-forward svc/zabbixprod-ui -n automated 8081:80

# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## Part 7: Troubleshooting Checklist

- [ ] Helm installed and verified
- [ ] ArgoCD CLI installed and verified
- [ ] ArgoCD installed with `controller.applicationNamespaces=""`
- [ ] Project allows `PersistentVolume` (PascalCase) as cluster resource - verify with `argocd proj get zabbix`
- [ ] Repository added and accessible (check `argocd repo list`)
- [ ] Target namespace exists
- [ ] PV and PVC have matching storage classes (check both have same `storageClassName`)
- [ ] Images pulled locally if cluster has network issues
- [ ] All pods in Running state
- [ ] Application shows as Synced and Healthy in ArgoCD

---

## Part 8: Key Configuration Points Summary

1. **ArgoCD Installation:** Must use `controller.applicationNamespaces=""` to allow cluster-scoped resources
2. **Project Configuration:** Must explicitly allow `PersistentVolume` (PascalCase singular) as cluster resource - **case-sensitive!**
3. **SSH Keys:** Required for private repositories, must be configured as a secret
4. **Storage Classes:** PV and PVC must have matching storage classes (both use empty string `""` by default)
5. **Image Pulls:** May need to pull images locally if cluster nodes have network issues
6. **Resource Kind Case:** Always use PascalCase singular form for Kubernetes resource kinds in ArgoCD project configuration
7. **Auto-Sync:** Applications are created with auto-sync enabled by default (automated, self-heal, auto-prune)

---

## Notes

- The `alpine` image pull issue is common in Docker Desktop Kubernetes due to network connectivity from cluster nodes to Docker Hub
- PersistentVolume binding issues often stem from storage class mismatches
- ArgoCD's namespaced mode is a security feature that restricts cluster-scoped resource management
- Always verify the project configuration includes cluster resource permissions before syncing
- **Critical:** Kubernetes resource kinds in ArgoCD project configuration must use PascalCase singular form (e.g., `PersistentVolume`, not `persistentvolumes` or `persistentvolume`)
- The default `storageClassName` in `values.yaml` is set to empty string `""` to ensure PV and PVC match on all Kubernetes distributions
- With auto-sync enabled, Git changes are automatically applied - no manual sync needed
