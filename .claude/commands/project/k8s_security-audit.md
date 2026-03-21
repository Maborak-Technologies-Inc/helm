Perform a security-focused audit of all Kubernetes resources in the Helm charts.

You are the **kubernetes-architect** agent with a security focus. Be thorough and opinionated.

---

## Procedure

### Step 1 — Read All Templates

Read every template in both charts. Focus on security-relevant fields.

### Step 2 — Pod Security Audit

For every container spec, check:

```bash
# Find containers without security context
grep -B5 -A20 "containers:" charts/*/templates/*.yaml | grep -A15 "name:"
```

| Check | Required Value | Risk if Missing |
|-------|---------------|-----------------|
| `runAsNonRoot` | `true` | Container runs as root — full node compromise if escaped |
| `allowPrivilegeEscalation` | `false` | Process can gain more privileges than parent |
| `readOnlyRootFilesystem` | `true` | Attacker can write malware to container filesystem |
| `capabilities.drop` | `["ALL"]` | Container retains unnecessary Linux capabilities |
| `seccompProfile.type` | `RuntimeDefault` | No syscall filtering |

### Step 3 — RBAC Audit

```bash
# Find ServiceAccount definitions
grep -rn "kind: ServiceAccount" charts/*/templates/
# Find ClusterRoleBindings (dangerous)
grep -rn "kind: ClusterRoleBinding" charts/*/templates/
# Find automountServiceAccountToken
grep -rn "automountServiceAccountToken" charts/*/templates/
```

- ServiceAccounts should be per-workload, not shared
- `automountServiceAccountToken: false` unless the pod needs k8s API access
- No ClusterRoleBindings unless absolutely necessary (prefer namespaced RoleBindings)

### Step 4 — NetworkPolicy Audit

```bash
# Find NetworkPolicy definitions
grep -rn "kind: NetworkPolicy" charts/*/templates/
```

- Default-deny ingress policy exists
- Each service has explicit ingress allow rules
- Egress is controlled (not wide open)
- Database only accepts connections from backend

### Step 5 — Secrets Audit

```bash
# Find Secret definitions
grep -rn "kind: Secret" charts/*/templates/
# Find hardcoded values that look like secrets
grep -rn "password\|secret\|token\|key" charts/*/values.yaml | grep -v "#"
# Find env vars referencing secrets
grep -rn "secretKeyRef\|valueFrom" charts/*/templates/
```

- No plaintext secrets in values.yaml defaults
- Secrets use Kubernetes Secret objects (not ConfigMaps)
- Secret values use `required` or are empty by default

### Step 6 — Image Security

```bash
# Find image references
grep -rn "image:" charts/*/templates/ charts/*/values.yaml
# Find imagePullPolicy
grep -rn "imagePullPolicy" charts/*/templates/ charts/*/values.yaml
```

- Images use specific tags (not `:latest`)
- `imagePullPolicy: IfNotPresent` (not `Always` unless using mutable tags)
- Private registry requires `imagePullSecrets`

### Step 7 — Ingress/Exposure Audit

- Ingress uses TLS
- No services exposed as `type: LoadBalancer` unnecessarily
- Host-based routing configured (not catch-all)
- CORS and security headers handled at ingress/application level

### Step 8 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  KUBERNETES SECURITY AUDIT
  Date: YYYY-MM-DD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Security Posture
[Status: HARDENED | ACCEPTABLE | VULNERABLE]

## Pod Security
| Workload | runAsNonRoot | noPrivEsc | readOnlyFS | dropCaps | seccomp | Score |

## RBAC
| ServiceAccount | Workload | ClusterRole? | AutoMount? | Issues |

## NetworkPolicy Coverage
| Service | Ingress Deny | Ingress Allow | Egress Control | Score |

## Secrets Management
| Secret | Source | Plaintext Risk? | Rotation? |

## Image Security
| Image | Tag Pinned? | PullPolicy | PullSecret? |

## Findings
| # | Severity | Category | Component | Issue | Fix |

## Recommendations
[Numbered, prioritized by severity — CRITICAL first]
```

---

## Rules

- CRITICAL: any finding that enables unauthorized access or privilege escalation
- HIGH: any finding that weakens defense-in-depth
- MEDIUM: missing best practice that increases attack surface
- Every finding must have a specific template file reference
