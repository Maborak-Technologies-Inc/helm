Synchronize all project artifacts — agents, commands, and CLAUDE.md — with the current chart state. Run after significant chart changes to eliminate stale references.

## Step 1 — Build the Truth Snapshot

Scan the repo in parallel:

**Chart inventory:**
```bash
find charts/ -name "Chart.yaml" -not -path "*/packaged/*" -exec cat {} \;
```

**Template inventory:**
```bash
ls -1 charts/amazon-watcher-stack/templates/*.yaml
ls -1 charts/zabbix/templates/*.yaml
```

**Values structure:**
```bash
grep -E "^[a-zA-Z]" charts/amazon-watcher-stack/values.yaml | head -40
grep -E "^[a-zA-Z]" charts/zabbix/values.yaml | head -40
```

**Helpers:**
```bash
grep -n "^{{- define" charts/amazon-watcher-stack/templates/_helpers.tpl
```

**CI/CD:**
```bash
ls .github/workflows/ 2>/dev/null
```

**Tooling inventories:**
```bash
ls -1 .claude/agents/core/*.md .claude/agents/project/*.md
ls -1 .claude/commands/core/*.md .claude/commands/project/*.md
ls -1 .claude/skills/*.md 2>/dev/null
```

**Git recent history:**
```bash
git log --oneline -10
```

Collect all outputs into a mental model. This is the **Truth Snapshot**.

---

## Step 2 — Refresh Agent Files

For each agent in `.claude/agents/core/` and `.claude/agents/project/`, read the full file and update **only factual sections**:

| Section type | Action |
|-------------|--------|
| Sources of Truth file lists | Add new files, remove deleted ones |
| Workload topology tables | Add new workloads from templates |
| Helper references | Update from _helpers.tpl scan |
| Values structure descriptions | Match current values.yaml |

### What to NEVER touch:

- Identity (role, scope, authority, tone)
- Methodology / evaluation criteria
- Output format templates
- Anti-pattern lists

**Skip rule**: If nothing in the Truth Snapshot affects an agent's factual sections, skip it entirely.

---

## Step 3 — Refresh CLAUDE.md

Read `CLAUDE.md`. Update these sections:

| Section | What to check |
|---------|--------------|
| Architecture tables | Match current templates |
| Template helpers | Match current _helpers.tpl |
| Values structure | Match current values.yaml |
| Common commands | Still correct? |
| Key conventions | Still accurate? |

---

## Step 4 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SYNC-ALL COMPLETE
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Agent Files
| Agent | Status | What Changed |
|-------|--------|-------------|

## CLAUDE.md
| Section | Status |
|---------|--------|

## Stale References Fixed
- [List any references that were outdated]

## New Items Discovered
- [Any templates, helpers, or values not previously documented]
```

---

## Rules

1. **This is a sync, not an audit** — update docs to match code reality
2. **Never rewrite agent identity** — only factual business context
3. **Skip agents with no stale facts**
4. **Every fact you write must be verifiable** against what you scanned
5. **Preserve formatting** — match existing markdown style
