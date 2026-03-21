Audit the CI/CD pipeline for Helm chart publishing and deployment.

You are the **devops** agent performing this audit.

---

## Procedure

### Step 1 — Discover Pipeline Artifacts

```bash
find .github/ -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort
find . -name "Makefile" -not -path "*/.git/*" 2>/dev/null
```

Read every workflow file found.

### Step 2 — Pipeline Coverage Assessment

Map each stage of the delivery lifecycle and whether it's automated:

| Stage | Exists? | Tool | File | Gaps |
|-------|---------|------|------|------|
| Chart lint | | | | |
| Template render/validate | | | | |
| Values schema validation | | | | |
| Kubeconform (k8s API schema) | | | | |
| Security scan (Trivy config) | | | | |
| Deprecated API check (Pluto) | | | | |
| Chart version bump check | | | | |
| Chart package | | | | |
| Chart repo index | | | | |
| Publish to GitHub Pages | | | | |
| Argo CD sync trigger | | | | |
| Smoke tests post-deploy | | | | |
| Rollback mechanism | | | | |

### Step 3 — Workflow Quality Check

For each workflow file:
- Triggers: push, PR, manual?
- Branches: main only, or also feature branches?
- Concurrency: can parallel runs corrupt the chart repo?
- Secrets: are they handled correctly?
- Caching: is helm cache utilized?
- Failure handling: does a failed step stop the pipeline?

### Step 4 — Chart Repository Assessment

```bash
ls charts/packaged/ 2>/dev/null
cat charts/packaged/index.yaml 2>/dev/null | head -30
```

- Is `index.yaml` properly maintained?
- Are old versions preserved?
- Is HTTPS enforced?
- Should the repo migrate to OCI (GHCR)?

### Step 5 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CI/CD PIPELINE AUDIT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Pipeline Assessment
[Coverage: N% of delivery lifecycle automated]
[Status: PRODUCTION-READY | NEEDS-WORK | MINIMAL]

## Stage-by-Stage Review
| Stage | Status | Tool | Gaps | Effort to Add |

## Workflow Quality
| Workflow | Triggers | Branches | Concurrency | Secrets | Issues |

## Chart Repository
| Concern | Status | Notes |

## Missing Stages (prioritized)
| # | Stage | Risk if Missing | Effort | Recommendation |

## Recommendations
[Numbered, prioritized by deployment safety]
```
