Audit all Kubernetes resources rendered by the Helm charts for correctness, security, and operational readiness.

You are the **kubernetes-architect** agent performing this audit. Apply your full evaluation criteria.

---

## Procedure

### Step 1 — Render All Templates

```bash
helm template audit-release charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml > /tmp/aws-rendered.yaml 2>&1
helm template audit-release charts/zabbix -f charts/zabbix/values.yaml > /tmp/zabbix-rendered.yaml 2>&1
```

### Step 2 — Inventory Resources

```bash
grep -E "^kind:" /tmp/aws-rendered.yaml | sort | uniq -c | sort -rn
grep -E "^kind:" /tmp/zabbix-rendered.yaml | sort | uniq -c | sort -rn
```

### Step 3 — Read All Templates

Read every template file in both charts:
- `charts/amazon-watcher-stack/templates/*.yaml`
- `charts/zabbix/templates/*.yaml`

### Step 4 — Workload Specification Audit

For each workload (Rollout, StatefulSet, Deployment, CronJob), check:

| Field | Check |
|-------|-------|
| `resources.requests` | Set? Reasonable values? |
| `resources.limits.memory` | Set? |
| `livenessProbe` | Present? Correct endpoint? |
| `readinessProbe` | Present? Different from liveness? |
| `startupProbe` | Present for slow-starting containers? |
| `securityContext.runAsNonRoot` | `true`? |
| `securityContext.allowPrivilegeEscalation` | `false`? |
| `securityContext.readOnlyRootFilesystem` | `true` where possible? |
| `terminationGracePeriodSeconds` | Set? |
| `imagePullPolicy` | `IfNotPresent` or `Always`? |

### Step 5 — Networking Audit

For each Service, Ingress, and NetworkPolicy:
- Service selectors match pod labels
- NetworkPolicy default-deny exists
- Ingress has TLS configured
- Port names are consistent between Service and container

### Step 6 — Storage Audit

For each PVC:
- AccessMode matches workload type (RWO for single-pod)
- StorageClass fallback works in dry-run
- Retention policy is safe for production data

### Step 7 — Scaling Audit

For each HPA:
- Target CPU ≤ 70%
- minReplicas ≥ 2 for P0/P1 services
- maxReplicas is reasonable
- HPA targets correct resource (Rollout, not Deployment)

For each PDB:
- minAvailable doesn't block node drains
- Covers all multi-replica workloads

### Step 8 — CronJob Audit

- `concurrencyPolicy` is set (Forbid or Replace)
- `activeDeadlineSeconds` is set
- `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` are set
- Schedule expression is valid

### Step 9 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  KUBERNETES RESOURCE AUDIT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Resource Inventory
| Chart | Kind | Name | Count |

## Workload Health Matrix
| Component | Kind | Resources | Probes | Security | Scheduling | Score |

## Networking Matrix
| Source | Destination | Port | NetworkPolicy | Status |

## Storage Review
| PVC | StorageClass | Size | AccessMode | Retention |

## Scaling Review
| Component | HPA Min | HPA Max | Target CPU | PDB | Anti-Affinity |

## Findings
| # | Severity | Component | Field | Current | Recommended | Template:Line |

## Recommendations
[Numbered, prioritized by security first, then reliability, then quality]
```
