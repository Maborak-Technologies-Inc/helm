Deep multi-agent audit of the latest changes to the Helm monorepo.

**Scope**: $ARGUMENTS

---

## Why this command exists

Helm changes look small in a diff but touch live cluster state on `helm upgrade`. A one-line `values.yaml` edit can drop a NetworkPolicy, demote a probe, or flip an image tag to `:latest`. A new template can render valid YAML but ship a workload with no resource limits, no security context, or a CrashLoopBackOff during rollout. CI publishes the chart minutes later, Argo CD syncs it, and the regression hits production before review catches it.

This command runs a parallel multi-agent audit over the changes you scope. Each specialist reviews their domain (templates, K8s resources, RBAC, GitOps, CI, reliability, Postgres if touched). Findings come back triaged CRITICAL → LOW so you can ship clean.

---

## Step 1 — Resolve scope

Pick what to audit based on `$ARGUMENTS`:

| Keyword | Resolves to |
|---|---|
| `pending` *(default)* | Working-tree changes (staged + unstaged), no commits |
| `staged` | Only staged changes (`git diff --cached`) |
| `worktree` | Only unstaged changes (`git diff`) |
| `recent` | Last commit (`HEAD`) |
| `unshipped` | Commits ahead of `origin/main` (`git log origin/main..HEAD`) |
| `<sha>` or `<sha1..sha2>` | Custom range |
| empty | Same as `pending` |

Run the appropriate `git diff` / `git log` once, capture file list + per-file diff. Print the chosen scope:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HELM AUDIT
  Scope: <keyword> → <N> files changed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If scope is empty, abort with a friendly note.

---

## Step 2 — Triage by dimension

Walk the file list and categorize each path. A file may belong to several categories — that's fine.

| Dimension | Path patterns | Lead agent(s) |
|---|---|---|
| Chart templates | `charts/*/templates/**/*.yaml`, `**/_helpers.tpl` | `helm-architect`, `kubernetes-architect` |
| Values / schema | `charts/*/values.yaml`, `charts/*/values.schema.json`, `charts/*/Chart.yaml` | `helm-architect` |
| K8s workloads (rendered) | Rollout / Deployment / StatefulSet / CronJob / DaemonSet templates | `kubernetes-architect`, `sre` |
| RBAC / SA / Policy | `serviceaccount.yaml`, `role*.yaml`, `clusterrole*.yaml`, `networkpolicy.yaml`, `*podsecurit*` | `security-auditor` |
| Secrets-shaped | `secret*.yaml`, `*.values.yaml` with `password`/`token`/`apiKey`/`secret` keys | `security-auditor`, `secrets-auditor` |
| Ingress / Gateway | `ingress.yaml`, `gateway.yaml`, `virtualservice.yaml` | `security-auditor`, `kubernetes-architect` |
| ArgoCD / Rollout | `argocd/*`, `application*.yaml`, `rollout*.yaml`, `analysistemplate*.yaml` | `argocd-architect`, `sre` |
| CI / publishing | `.github/workflows/**`, `scripts/**`, `Dockerfile`, `Makefile` | `devops` |
| Cluster bootstrap | `kubernetes/**`, `kubernetes/bootstrap/**` | `devops`, `kubernetes-architect` |
| Postgres / Patroni | anything matching `patroni`, `postgres`, `pgbouncer`, `barman` | `postgres-dba` |
| Docs / README | `docs/**`, `**/README.md`, `**/CHANGELOG.md` | skip (note only) |

Print the triage table before dispatching so the user sees who you're calling.

---

## Step 3 — Flag pre-existing modifications

For each file in the scope, check whether the change matches the commit message theme (or the user's stated intent). Files modified incidentally — "while I was there" — get a separate **Drift** section in the report. They often hide regressions because they weren't mentally part of the change.

Heuristic:
- Look at the commit subject line; extract the noun/verb.
- Files outside that scope go into Drift.
- Don't be precious — surface them all, the user decides whether they're intentional.

---

## Step 4 — Dispatch specialists in parallel

Launch the agents identified in Step 2 **in a single message, multiple Agent tool calls** so they run concurrently. Each agent gets:

- The relevant slice of the diff (only the files they own — don't drown them in unrelated changes).
- A short brief: "audit these changes for <agent's domain>; flag anything risky for rollout, security, reliability, or correctness".
- Tag instruction: prefix every finding with `[committed]` if it's in a commit you reviewed, `[uncommitted]` if it's working-tree only.
- Output contract: severity (CRITICAL/HIGH/MEDIUM/LOW), file:line, one-sentence problem, one-sentence fix.

Always include `helm-architect` if any chart file changed — they own template correctness end-to-end.

---

## Step 5 — Cross-check against the Helm landmine catalogue

After agent results return, scan every changed file for these known regressions. If found, escalate the matching agent finding to CRITICAL (or add a new CRITICAL if no agent flagged it):

| # | Landmine | Grep / detection |
|---|---|---|
| 1 | **`:latest` image tag** | `image:.*:latest`, `tag:\s*latest`, `tag:\s*""` (empty) |
| 2 | **No resource limits** on a Deployment/Rollout/StatefulSet | template renders a container with no `resources.limits` block |
| 3 | **`privileged: true`** | grep templates + rendered output |
| 4 | **`hostNetwork: true` / `hostPID` / `hostIPC`** | flag unless explicitly required (node-exporter, calico) |
| 5 | **runAsNonRoot missing** on new workload | `securityContext` block absent or missing the field |
| 6 | **NetworkPolicy gap** | new workload added without a matching NetworkPolicy in the same chart |
| 7 | **Probe regression** | `readinessProbe` removed, `livenessProbe` without `readinessProbe`, `initialDelaySeconds` < probe period, `failureThreshold: 1` |
| 8 | **HPA without resource requests** | HPA added but pod has no `resources.requests.cpu` / `memory` |
| 9 | **PVC without storageClassName** AND `WaitForFirstConsumer` | stuck Pending in environments without a default class |
| 10 | **Plaintext secret in values** | regex on values.yaml for `password|secret|token|apiKey|api_key` next to a non-empty string |
| 11 | **ConfigMap mounted without checksum annotation** | `configMap:` in volumes without `checksum/config` pod annotation → no reload on upgrade |
| 12 | **emptyDir on stateful workload** | StatefulSet / Patroni / DB component using emptyDir for data path |
| 13 | **Argo Rollout strategy regression** | `strategy.canary.steps` removed/shortened, `analysis` block removed, `trafficRouting` removed |
| 14 | **Sync policy too aggressive** | `automated.prune: true` + `selfHeal: true` added to a production Application without `syncOptions: CreateNamespace=false, FailOnSharedResource=true` |
| 15 | **Helm helper rename breaks references** | `_helpers.tpl` defined name changed, but other templates still call old name |
| 16 | **values.schema.json drift** | values.yaml field added/removed but schema not updated → consumer charts break |
| 17 | **PDB on a 1-replica workload** | `minAvailable: 1` / `maxUnavailable: 0` on 1-replica = blocks every node drain |
| 18 | **Service selector mismatch after rename** | Service `selector` labels diverge from Pod labels |
| 19 | **Default-namespace creep** | new template using `metadata.namespace: default` instead of `.Release.Namespace` |
| 20 | **Image pulled with `Always`** + mutable tag | risk of stale image on restart |
| 21 | **Chart.yaml version not bumped** | template change without `version:` bump → CI publishes same .tgz |
| 22 | **NetworkPolicy egress overly permissive** | egress `{}` or `to: []` on workloads that should only talk to specific services |

Don't fabricate. If grep finds nothing, the landmine doesn't apply.

---

## Step 6 — Synthesize report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AUDIT REPORT — <scope>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Verdict
[SHIP IT | NEEDS FIXES | DO NOT MERGE]

## Counts
CRITICAL: N | HIGH: M | MEDIUM: K | LOW: J

## Findings (CRITICAL first)
| # | Sev | Agent | File:Line | Problem | Fix |

## Drift (files outside the stated theme)
- path — why it's odd

## Landmines triggered
- # — landmine name — file:line

## What looks good
- (one or two sentences, optional — keeps morale honest)

## Next steps
1. ...
2. ...
```

---

## Cardinal rules

1. **Never claim "audit complete" without naming every agent you actually called.** If you called 4 of 6 because the diff was small, say so.
2. **Don't fabricate findings.** Only report what agents returned or what landmine grep matched.
3. **Whole-file audit for runtime-critical files.** If the diff touches `_helpers.tpl`, `bootstrap.sh`, an Argo Rollout strategy block, or anything under `kubernetes/bootstrap/`, ask the specialist to read the entire file — not just the hunk. Small diffs in these files have outsize blast radius.
4. **Diff-aware briefing.** Every agent prompt MUST include the actual diff content for their files, not just file paths.
5. **Parallelism first.** Round 1 of agent dispatch is always a single message with multiple Agent tool calls. Sequential calls waste minutes per audit.
6. **Severity discipline.** CRITICAL = ship-blocking. HIGH = ship-soon. MEDIUM = next sprint. LOW = nit. Don't inflate.
7. **Surface the unstated change.** If a file in the diff doesn't appear to match the user's described intent, put it in Drift even if it's "fine" on its own — drift is how regressions sneak in.
