# Amazon Watcher Helm — Claude Project Context

**Source of truth**: the code. When code and this file conflict, the code wins.

---

## Framework

This project follows the .claude Framework convention. See .claude/FRAMEWORK.md for the full specification.

Key locations:
- **Memory**: .claude/memory/ (MEMORY.md + feedback/ + snapshots/)
- **Tracking**: .claude/tracking/ (TODO.md, CHANGELOG.md)
- **Core agents**: .claude/agents/core/ (framework-expert, session-commit)
- **Project agents**: .claude/agents/project/ (helm-architect, kubernetes-architect, argocd-architect, security-auditor, devops, sre, postgres-dba, incident-commander, supply-chain-auditor, secrets-auditor, threat-modeler, compliance-auditor)
- **Core commands**: .claude/commands/core/ (session-commit, sync-all)
- **Project commands**: .claude/commands/project/ (helm_*, k8s_*, argocd_*, devops_*, sre_*, deploy_readiness, meet, audit, incident, security)
- **Skills**: .claude/skills/ (add-service, add-environment, add-cronjob)

---

## Maintenance Rules

When creating a new agent or command:
1. Core agents/commands go in .claude/agents/core/ or .claude/commands/core/
2. Project agents/commands go in .claude/agents/project/ or .claude/commands/project/
3. Add to the Commands table below
4. Update .claude/memory/MEMORY.md

---

## Project Structure

| Folder | Purpose | Stack |
|--------|---------|-------|
| charts/amazon-watcher-stack | Primary application chart | Helm 3, Argo Rollouts |
| charts/zabbix | Monitoring stack chart | Helm 3, Zabbix 7.4.6 |
| charts/packaged | Published chart packages | .tgz |
| docs/ | Human-readable documentation | Markdown |
| kubernetes/ | Cluster bootstrap scripts | Bash |
| scripts/ | Utility scripts | Bash |
| .github/workflows/ | CI/CD pipelines | GitHub Actions |

## Commands

| Command | Type | Purpose |
|---------|------|---------|
| /session-commit | Core | End-of-session commit + CHANGELOG + memory |
| /sync-all | Core | Synchronize all project artifacts |
| /helm_lint-all | Project | Lint all charts |
| /helm_chart-audit | Project | Full Helm chart quality audit |
| /k8s_resource-audit | Project | Audit rendered Kubernetes resources |
| /k8s_security-audit | Project | Security audit of K8s resources |
| /argocd_sync-review | Project | Review Argo CD sync health |
| /sre_reliability-audit | Project | Full reliability audit |
| /devops_pipeline-audit | Project | CI/CD pipeline audit |
| /deploy_readiness | Project | Pre-deployment readiness check |
| /meet | Project | Multi-agent team discussion |
| /audit | Project | Deep multi-agent audit of latest changes (scope-aware) |
| /incident | Project | Active-incident coordination via incident-commander + specialists |
| /security | Project | Five-seat security review (k8s, supply-chain, secrets, threat model, compliance) |

## Development Environment

```bash
# Lint charts
helm lint charts/amazon-watcher-stack
helm lint charts/zabbix

# Render templates locally
helm template my-release charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml
helm template my-release charts/zabbix -f charts/zabbix/values.yaml

# Package
helm package charts/amazon-watcher-stack --destination charts/packaged
```

---

# Amazon Watcher Helm Monorepo

## Project Identity
- **Purpose**: GitOps Helm chart monorepo for the Amazon Watcher platform and Zabbix monitoring
- **Architecture**: Multi-chart monorepo, GitOps via Argo CD, canary deployments via Argo Rollouts
- **Stack**: Helm 3, Kubernetes, Argo CD, Argo Rollouts, GitHub Actions

## Architecture Rules
- All application workloads use Argo **Rollouts**, not Deployments (except maborak utility and zabbix)
- NetworkPolicies follow default-deny with explicit allow rules per service
- Pod security: non-root users, no privilege escalation, read-only root filesystem where possible
- Environment variables carry component prefix (`APT_BACKEND_*`, `VITE_*`)
- Computed env vars are injected in templates, not in values

## Key Files
| File | Purpose |
|------|---------|
| charts/amazon-watcher-stack/values.yaml | Primary chart defaults |
| charts/amazon-watcher-stack/templates/_helpers.tpl | Template helper functions |
| charts/zabbix/values.yaml | Zabbix chart defaults |
| .github/workflows/helm-publish.yml | CI publish pipeline |
| kubernetes/bootstrap/bootstrap.sh | Cluster bootstrap script |
| CLAUDE.md | Root project context (human-facing) |
