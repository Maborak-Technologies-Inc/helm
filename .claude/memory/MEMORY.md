# Amazon Watcher Helm — Persistent Memory

## Project Structure
Helm chart monorepo with two charts:
- `charts/amazon-watcher-stack` — primary app chart (FastAPI backend, React UI, PostgreSQL, Chromium screenshot service)
- `charts/zabbix` — monitoring chart (Zabbix server + web + MariaDB)
- `charts/packaged` — published .tgz packages
- `kubernetes/` — cluster bootstrap scripts
- `docs/` — human documentation
- `.github/workflows/` — CI (helm-publish.yml)

## Key Files
| File | Purpose |
|------|---------|
| charts/amazon-watcher-stack/values.yaml | Primary chart defaults |
| charts/amazon-watcher-stack/templates/_helpers.tpl | Template helpers |
| charts/zabbix/values.yaml | Zabbix defaults |
| .github/workflows/helm-publish.yml | CI publish pipeline |
| CLAUDE.md | Root project context |
| .claude/CLAUDE.md | Framework context |

## Slash Commands
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

## Agents
### Core
- framework-expert — .claude framework maintenance, auditing, scaffolding
- session-commit — end-of-session workflow

### Project
- helm-architect — Helm chart design, template helpers, values schema
- kubernetes-architect — K8s workload specs, scheduling, networking, storage, RBAC
- argocd-architect — Argo CD Applications, sync policies, Rollouts canary/blue-green
- security-auditor — Pod security contexts, RBAC, NetworkPolicies, secrets management
- devops — CI/CD pipelines, chart publishing, image builds, GitHub Pages
- sre — Reliability, HPA, PDB, health probes, canary analysis, observability

## Last Session
Date: 2026-03-20
Branch: main
Summary: Project initialization — .claude framework v2.0 bootstrapped (core/project split, memory, tracking)

### Remaining Work
- Review and customize project agent files for latest chart state
- Add architecture rules to .claude/CLAUDE.md as they are discovered
