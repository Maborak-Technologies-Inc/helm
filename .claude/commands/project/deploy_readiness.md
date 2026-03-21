Run a pre-deployment readiness gate check for the Helm charts. This is a fast, targeted check — not a full audit. Use it before every chart publish or Argo CD sync.

You are the **devops** agent performing this check. Be fast, precise, and opinionated.

---

## Procedure

### Step 1 — Read Current State

```bash
git status --short
git diff --stat HEAD~1
git log --oneline -5
```

Read `charts/amazon-watcher-stack/Chart.yaml` and `charts/zabbix/Chart.yaml` for current versions.

### Step 2 — Run Gate Checks

Execute each check and record PASS / FAIL / WARN:

#### Chart Lint (CRITICAL — BLOCK on FAIL)

```bash
helm lint charts/amazon-watcher-stack --strict 2>&1
helm lint charts/zabbix --strict 2>&1
```

#### Template Render (CRITICAL — BLOCK on FAIL)

```bash
helm template test charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml > /dev/null 2>&1; echo "Exit: $?"
helm template test charts/zabbix -f charts/zabbix/values.yaml > /dev/null 2>&1; echo "Exit: $?"
```

#### Version Bump Check (HIGH — BLOCK on FAIL)

Compare current chart versions against the last published versions:

```bash
# Check if version was bumped since last commit
git diff HEAD~1 -- charts/amazon-watcher-stack/Chart.yaml | grep "^[+-]version:"
git diff HEAD~1 -- charts/zabbix/Chart.yaml | grep "^[+-]version:"
```

If chart templates changed but version didn't bump → FAIL.

#### Secrets in Values (CRITICAL — BLOCK on FAIL)

```bash
# Check for hardcoded secrets in values files
grep -rn "password:.*[a-zA-Z]" charts/*/values.yaml | grep -v "# " | grep -v '""' | grep -v "''"
grep -rn "secret:.*[a-zA-Z]" charts/*/values.yaml | grep -v "# " | grep -v '""' | grep -v "''"
```

Any non-empty secret value in defaults → FAIL.

#### Resource Limits Check (MEDIUM — WARN)

```bash
# Check all containers have resource requests
grep -c "resources:" charts/amazon-watcher-stack/templates/*.yaml
grep -c "requests:" charts/amazon-watcher-stack/templates/*.yaml
```

If any workload is missing `resources.requests` → WARN.

#### Image Tag Check (MEDIUM — WARN)

```bash
grep "tag:" charts/*/values.yaml
```

If any image uses `latest` → WARN.

### Step 3 — Produce Gate Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DEPLOY READINESS GATE
  Date: YYYY-MM-DD
  Decision: ✅ GO | ⚠️ GO WITH CONDITIONS | ❌ NO-GO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Gate Results

| # | Check | Status | Detail |
|---|-------|--------|--------|
| 1 | Chart lint (strict) | ✅/❌ | |
| 2 | Template render | ✅/❌ | |
| 3 | Chart version bumped | ✅/❌ | |
| 4 | No secrets in values | ✅/❌ | |
| 5 | Resource limits set | ✅/⚠️ | |
| 6 | No :latest image tags | ✅/⚠️ | |

## Blocking Issues
[List any ❌ items with exact file:line and fix required]

## Conditions (if GO WITH CONDITIONS)
[List any ⚠️ items that should be resolved]

## Pre-Deploy Commands
```bash
# Package charts
helm package charts/amazon-watcher-stack --destination charts/packaged
helm package charts/zabbix --destination charts/packaged
helm repo index charts/packaged --url https://maborak-technologies-inc.github.io/helm
```

## Post-Deploy Validation
```bash
# Verify Argo CD sync status
argocd app list
argocd app get <app-name> --refresh
```
```

---

## Rules

- Keep it fast — this is a gate check, not an audit
- A single CRITICAL FAIL = NO-GO, no exceptions
- Multiple WARNs can be GO if they're non-production concerns
