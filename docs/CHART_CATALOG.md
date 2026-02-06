# Helm Chart Catalog

## amazon-watcher-stack
**Purpose**: Multi-service application stack for Amazon product monitoring and price tracking.

### Components
- **Backend API**: FastAPI REST service for business logic.
- **Web UI**: React frontend served via NGINX.
- **Screenshot Service**: Headless browser (Playwright/Chromium) for web scraping.
- **PostgreSQL**: Stateful database for data persistence.

### Key Configuration Knobs (values.yaml)
| Parameter | Description | Default |
|-----------|-------------|---------|
| `backend.replicas` | Number of API pods | `2` |
| `backend.autoscaling.enabled` | Enable HPA for API | `true` |
| `ui.replicas` | Number of UI pods | `1` |
| `screenshot.replicas` | Number of screenshot service pods | `1` |
| `ingress.enabled` | Enable Ingress routing | `true` |
| `ingress.className` | Ingress controller class | `nginx` |
| `storage.storageClass` | Storage class for PostgreSQL | `""` (Cluster default) |
| `global.revisionHistoryLimit` | Default old ReplicaSets to retain | `10` |
| `database.storage.pvcRetentionPolicy` | Delete/Retain PVCs on scaledown/delete | `Retain` |
| `database.storage.subPath` | Mount sub-directory of volume | `""` |
| `istio.enabled` | Enable Istio service mesh resources | `false` |

### Required Secrets / Config
- **PostgreSQL Credentials**: Database user, password, and DB name.
- **JWT Secret**: Required for backend authentication (often generated via Job).
- **Environment Variables**: API URLs, database connection strings.

### Typical Install Command
```bash
helm install my-watcher ./charts/amazon-watcher-stack \
  --namespace watcher \
  --set ingress.enabled=true
```

---

## zabbix
**Purpose**: Enterprise-grade monitoring solution with a server-web-database architecture.

### Components
- **Zabbix Server**: Core monitoring engine.
- **Zabbix UI**: PHP-based web management interface.
- **MariaDB**: Database backend for monitoring data.

### Key Configuration Knobs (values.yaml)
| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.storageClass` | Storage class for PVs | `""` (Cluster default) |
| `storage.mariadb.size` | PVC size for database | `5Gi` |
| `resources.server.limits` | CPU/Memory limits for Zabbix Server | (Configured in values) |
| `resources.ui.limits` | CPU/Memory limits for Zabbix UI | (Configured in values) |

### Required Secrets / Config
- **Database Passwords**: `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`.
- **Zabbix Credentials**: Initial admin credentials.

### Typical Install Command
```bash
helm install my-zabbix ./charts/zabbix \
  --namespace monitoring \
  --set storage.storageClass=standard
```

---

## Packaged Charts
- Located in `charts/packaged/`.
- Includes pre-built `.tgz` files for versioned distribution.
- `zabbix-stack-0.1.0.tgz`: Versioned build of the Zabbix chart.
