Perform a full reliability audit of all workloads defined in the Helm charts.

You are the **sre** agent performing this audit. Apply your full evaluation framework.

---

## Procedure

### Step 1 — Read Platform Context

Read these files first:
1. `CLAUDE.md` — architecture, workload topology, deployment model
2. `charts/amazon-watcher-stack/values.yaml` — resource defaults, HPA config, probe config
3. All templates in `charts/amazon-watcher-stack/templates/`

### Step 2 — Health Probe Audit

For every long-running workload, verify:

| Probe | Required | Check |
|-------|----------|-------|
| `livenessProbe` | YES | Present? Correct endpoint? Not checking dependencies? |
| `readinessProbe` | YES | Present? Different threshold from liveness? |
| `startupProbe` | For slow containers | Present for database, backend? |

```bash
grep -B2 -A10 "livenessProbe\|readinessProbe\|startupProbe" charts/amazon-watcher-stack/templates/*.yaml
```

Flag: identical liveness and readiness probes (copy-paste anti-pattern).
Flag: liveness probe checking database (cascading restart risk).

### Step 3 — Resource Management Audit

```bash
grep -B5 -A10 "resources:" charts/amazon-watcher-stack/templates/*.yaml
```

- `requests` set for all containers (scheduler needs this)
- `limits.memory` set for all containers (OOMKill protection)
- Values are reasonable (not 10m CPU for an API server)

### Step 4 — Scaling Audit

```bash
grep -B2 -A15 "kind: HorizontalPodAutoscaler" charts/amazon-watcher-stack/templates/*.yaml
```

- `minReplicas` ≥ 2 for P0/P1 services
- Target CPU ≤ 70%
- HPA targets Rollout (not Deployment)
- PDB exists for every multi-replica workload

### Step 5 — Failure Mode Analysis

For each component in the workload topology:

| Component | Failure Mode | Detection | Impact | Recovery |
|-----------|-------------|-----------|--------|----------|

Consider: pod crash, node drain, resource exhaustion, config drift, network partition, database failure.

### Step 6 — Canary Rollout Analysis

Read the canary strategy configuration:

```bash
grep -A30 "canary:" charts/amazon-watcher-stack/templates/*.yaml
```

- Are there analysis gates between weight steps?
- Does the AnalysisTemplate check real SLIs?
- Is automatic rollback configured on failure?

### Step 7 — Anti-Affinity and Topology

```bash
grep -B2 -A10 "affinity\|topologySpread" charts/amazon-watcher-stack/templates/*.yaml
```

- P0/P1 services spread across nodes
- Database not co-located with API on same node

### Step 8 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RELIABILITY AUDIT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Reliability Assessment
[Status: HEALTHY | DEGRADED | AT RISK]

## Workload Health Matrix
| Component | Kind | Probes | Resources | HPA | PDB | Anti-Affinity | Score |

## Failure Mode Analysis
| Component | Failure Mode | Detection | TTD | TTR | Mitigation | Gap |

## Canary Rollout Assessment
| Component | Strategy | Steps | Analysis | Rollback | Issues |

## SLI/SLO Proposals
| Service | SLI | Target SLO | Measurement |

## Findings
| # | Severity | Component | Issue | Impact | Recommendation |

## Action Items
| # | Action | Priority | Effort | Blocking? |
```
