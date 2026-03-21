Review the Argo CD GitOps configuration and sync health for all environments.

You are the **argocd-architect** agent performing this review.

---

## Procedure

### Step 1 — Read Argo CD Configuration

Read these files:
1. `CLAUDE.md` — deployment model, sync policy, namespace strategy
2. `docs/` — all Argo CD setup scripts

```bash
find docs/ -name "*argocd*" -o -name "*argo*" | sort
ls docs/*.sh 2>/dev/null
```

Read every Argo CD-related script found.

### Step 2 — Analyze Application Definitions

For each Argo CD Application definition found in scripts or docs:

| Setting | Check |
|---------|-------|
| `syncPolicy.automated` | Appropriate for the environment? |
| `syncPolicy.automated.prune` | Enabled? Tested? |
| `syncPolicy.automated.selfHeal` | Enabled? |
| `ignoreDifferences` | Includes `/spec/replicas` for HPA-managed Rollouts? |
| `project` | Environment-isolated? |
| `source.repoURL` | Points to correct chart repo? |
| `source.targetRevision` | Pinned or HEAD? |
| `destination.namespace` | Matches intended environment? |

### Step 3 — Analyze Rollout Strategies

Read all Rollout templates and evaluate:

```bash
grep -A30 "strategy:" charts/amazon-watcher-stack/templates/*.yaml
```

- Canary steps have analysis gates (not just time-based)
- AnalysisTemplates check real metrics
- Rollback is automatic on failure
- `maxUnavailable` and `maxSurge` preserve capacity

### Step 4 — Check for Sync Conflicts

Known conflict patterns to verify:

| Conflict | How to Check |
|----------|-------------|
| HPA vs replicas | Is `/spec/replicas` in `ignoreDifferences`? |
| Rollout status | Is `/status` ignored? |
| Secret rotation | Are Secret data fields ignored? |
| ConfigMap checksums | Are checksums deterministic from values? |

### Step 5 — Environment Promotion Assessment

Evaluate the promotion model:

| Environment | Sync Mode | Approval Gate | Chart Version | Values Override |
|-------------|----------|---------------|---------------|----------------|

### Step 6 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ARGO CD GITOPS REVIEW
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## GitOps Health
[Status: HEALTHY | DRIFT RISK | MISCONFIGURED]

## Application Configuration
| Application | Namespace | Sync Policy | Prune | SelfHeal | IgnoreDiffs | Issues |

## Rollout Strategy Review
| Component | Strategy | Steps | Analysis Template | Rollback Gate | Issues |

## Sync Conflict Analysis
| Conflict Type | Handled? | How | Risk if Not |

## Environment Promotion
| Env | Source | Sync Mode | Approval | Chart Pin | Issues |

## Findings
| # | Severity | Category | Issue | Recommendation |

## Recommendations
[Numbered, prioritized by sync stability]
```
