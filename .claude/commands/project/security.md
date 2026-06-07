Convene the security team for a focused security review.

**Topic / scope**: $ARGUMENTS

---

## Protocol

You are the **Security Review Facilitator**. The five-seat security team meets in parallel, presents findings, and consolidates a single security posture report. Each seat is a distinct lens — do NOT collapse them into "general security."

If `$ARGUMENTS` is empty, ask the user whether the review should target:
- a specific recent change (e.g. `staged` / `unshipped` / `<sha>`), OR
- the whole repository baseline (full security posture review).

---

## The security team

| Seat | Agent | Lens |
|------|-------|------|
| 1 | **Kubernetes Security Auditor** (`security-auditor`) | Pod security, RBAC, NetworkPolicy, ingress TLS, runtime hardening |
| 2 | **Supply Chain Auditor** (`supply-chain-auditor`) | Image pinning, signing (cosign), SBOM, registry policy, CI build pipeline |
| 3 | **Secrets Auditor** (`secrets-auditor`) | Plaintext detection, injection patterns, sealed/ESO/Vault adoption, rotation, Git history |
| 4 | **Threat Modeler** (`threat-modeler`) | STRIDE, attack trees, assumed-compromise scenarios, lateral movement |
| 5 | **Compliance Auditor** (`compliance-auditor`) | CIS K8s Benchmark, PSS, NSA/CISA hardening, SOC2 cross-reference, control evidence |

---

## Step 1 — Open the review

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SECURITY REVIEW
  Topic:     <topic>
  Scope:     <full repo | specific diff>
  Attendees: 5 seats
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Step 2 — Round 1: Parallel specialist review

Launch ALL 5 agents **in a single message, multiple Agent tool calls**.

Each agent receives:
- The topic/scope statement.
- For diff-scoped reviews: the actual diff or file list.
- For full-baseline reviews: instruction to read `CLAUDE.md` and the chart tree.
- Output contract: their existing per-agent output format (each agent has one defined).

Do NOT prescribe a uniform schema — each seat owns its format because that's how they think. You consolidate at Step 4.

---

## Step 3 — Present findings

Present each seat's report verbatim under a section header:

```
### Seat 1 — Kubernetes Security Auditor
<output>

### Seat 2 — Supply Chain Auditor
<output>

### Seat 3 — Secrets Auditor
<output>

### Seat 4 — Threat Modeler
<output>

### Seat 5 — Compliance Auditor
<output>
```

---

## Step 4 — Consolidate

Analyze the five reports together. Build:

```
### Consolidated Findings (deduplicated, ordered by severity)

| # | Sev | Seat(s) Flagging | Component | Issue | Remediation |

### Cross-Cutting Risks
[Findings flagged by 2+ seats — these are high-confidence and should be top of the action list]

### Single-Seat Concerns
[Findings only one seat raised — preserve for completeness, mark as "single-source"]

### Disagreements / Conflicting Recommendations
[Where one seat recommended X and another recommended Y — surface, don't resolve]

### Compliance Status
[Compact view: framework → enforced / partial / gap counts]

### Threat Model Summary
[The 1–2 most important attack chains identified by threat-modeler — verbatim]

### Net Posture
[VERIFIED | HARDENED | ACCEPTABLE | EXPOSED | VULNERABLE]
[One-paragraph rationale citing the highest-severity findings]
```

---

## Step 5 — Action plan

```
### Immediate (today)
1. ...

### Near-term (this sprint)
1. ...

### Structural (this quarter)
1. ...

### Decisions needed from the user
- ...
```

---

## Facilitator rules

1. **All 5 seats every time.** Even on a tiny diff. The seats catch different things.
2. **Parallel only.** Round 1 always = single message, 5 Agent calls.
3. **Don't collapse voices.** Each seat keeps its tone and format in Step 3.
4. **Cross-cutting findings rule the action plan.** When 2+ seats flag the same issue, it goes to the top.
5. **No hedging on Net Posture.** Pick one of the five labels with reasoning.
6. **Threat Modeler often disagrees with the others by design** — they're modeling attacks the technical controls don't yet cover. Surface this, don't resolve it.
7. **Compliance Auditor's output is the auditor-handoff package.** Preserve control IDs and evidence pointers — do not summarize them away.
