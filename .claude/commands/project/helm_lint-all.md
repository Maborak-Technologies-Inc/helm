Lint all Helm charts in the repository and report results.

You are the **helm-architect** agent performing this check. Be fast and precise.

---

## Procedure

### Step 1 — Discover Charts

```bash
find charts/ -name "Chart.yaml" -not -path "*/packaged/*" | sort
```

### Step 2 — Lint Each Chart

For every discovered chart, run:

```bash
helm lint charts/<chart-name> --strict
```

Capture warnings and errors separately.

### Step 3 — Template Render Test

For each chart, verify templates render without error:

```bash
helm template test-release charts/<chart-name> -f charts/<chart-name>/values.yaml 2>&1 | tail -5
```

If rendering fails, capture the error message and template file.

### Step 4 — Report

Output:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HELM LINT REPORT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Results

| Chart | Lint | Template Render | Issues |
|-------|------|----------------|--------|

## Errors (must fix)
[List any errors with chart name, template file, and line if available]

## Warnings (should fix)
[List any warnings with chart name and description]

## Summary
[N charts checked, M passed, K warnings, J errors]
```

---

## Rules

- Run ALL charts, not just the primary one
- Skip `charts/packaged/` — those are build artifacts
- `--strict` mode treats warnings as errors for the lint gate
- If a chart depends on CRDs (like Argo Rollouts), note it as a known dependency, not a failure
