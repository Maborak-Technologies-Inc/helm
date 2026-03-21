Perform a full quality audit of all Helm charts in this repository.

You are the **helm-architect** agent performing this audit. Apply your full methodology and evaluation framework.

---

## Procedure

### Step 1 — Read Chart Context

Read these files first:
1. `CLAUDE.md` — architecture, conventions, helpers reference
2. `charts/amazon-watcher-stack/Chart.yaml` — chart metadata
3. `charts/amazon-watcher-stack/values.yaml` — full values tree
4. `charts/amazon-watcher-stack/templates/_helpers.tpl` — all helpers
5. `charts/zabbix/Chart.yaml` and `charts/zabbix/values.yaml`

### Step 2 — Chart Structure Check

For each chart, verify:

```bash
# Required files
for chart in charts/amazon-watcher-stack charts/zabbix; do
  echo "=== $chart ==="
  ls -la $chart/Chart.yaml $chart/values.yaml $chart/templates/_helpers.tpl $chart/templates/NOTES.txt $chart/.helmignore 2>&1
done
```

```bash
# Check for values.schema.json
find charts/ -name "values.schema.json" -not -path "*/packaged/*"
```

### Step 3 — Chart.yaml Validation

For each chart:
- `apiVersion` should be `v2`
- `version` follows semver
- `appVersion` is set
- `description` is meaningful
- `maintainers` list is populated

### Step 4 — Values Quality Audit

Read `values.yaml` for each chart and assess:
- Are all sections documented with comments?
- Are defaults sensible (chart renders with zero overrides)?
- Are there any secrets in default values?
- Are image references structured as `{ repository, tag, pullPolicy }`?
- Are feature flags boolean (`enabled: true/false`)?

### Step 5 — Template Quality Audit

Read all templates and check for:
- `include` vs `template` usage (should be `include`)
- Quoted string values (`| quote`)
- `default` or `required` on optional/mandatory values
- `nindent` vs `indent` usage
- Hardcoded namespaces
- `lookup` with fallback for CI dry-runs
- Correct label selectors (matchLabels matches template labels)

```bash
# Find template anti-patterns
grep -rn "{{ template " charts/*/templates/ --include="*.yaml" --include="*.tpl"
grep -rn "indent " charts/*/templates/ --include="*.yaml" | grep -v nindent
```

### Step 6 — Helper Audit

Read `_helpers.tpl` and verify:
- All helpers are namespaced with chart name
- Env iteration helpers skip computed vars correctly
- Checksum helpers cover all config sources
- StorageClass fallback chain works during `helm template` (no cluster)

### Step 7 — Lint and Render

```bash
helm lint charts/amazon-watcher-stack --strict 2>&1
helm lint charts/zabbix --strict 2>&1
helm template test charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml 2>&1 | head -20
helm template test charts/zabbix -f charts/zabbix/values.yaml 2>&1 | head -20
```

### Step 8 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HELM CHART AUDIT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Chart Quality Assessment
[Status: PRODUCTION-READY | NEEDS-WORK | BROKEN]

## Structure Review
| Chart | Chart.yaml | values.yaml | _helpers.tpl | NOTES.txt | .helmignore | Schema |

## Values Quality
| Chart | Section | Defaults OK? | Secrets? | Comments? | Issues |

## Template Quality
| Chart | Template | Anti-Patterns | Issues |

## Helper Quality
| Helper | Correct? | Issues |

## Lint & Render Results
| Chart | Lint | Render | Errors |

## Findings (prioritized)
| # | Severity | Chart | File:Line | Issue | Recommendation |

## Recommendations
[Numbered, prioritized by rendering correctness first, then quality]
```

---

## Rules

- Every finding must reference a specific file and line
- Distinguish between "breaks rendering" (CRITICAL) and "suboptimal" (WARN)
- Check both charts, not just the primary one
- If `values.schema.json` is missing, recommend creating one
