# .claude Framework — Bootstrap Gateway v2.0

You are reading this because a human asked you to set up the `.claude` framework in this project. This is a self-contained document — everything you need is here. No external files required.

This framework separates **core** (universal infrastructure) from **project** (tailored to this specific codebase). You will install the core, then discover the project and propose appropriate agents.

---

## Part 1: Install Framework Core

This part is automatic — do it for every project.

### 1a. Create Directory Structure

```bash
mkdir -p .claude/agents/core .claude/agents/project
mkdir -p .claude/commands/core .claude/commands/project
mkdir -p .claude/skills
mkdir -p .claude/memory/feedback .claude/memory/snapshots
mkdir -p .claude/tracking
mkdir -p .claude/brainstorm/specs .claude/brainstorm/plans
```

For monorepos, also create `_claude/` in each submodule's docs:
```bash
mkdir -p {submodule}/docs/_claude
```

### 1b. Write Core Agents

#### `.claude/agents/core/framework-expert.md`

```markdown
---
name: framework-expert
description: |
  .claude framework specialist. Use this agent to: audit the .claude/ setup
  for compliance, scaffold new agents/commands/skills following conventions,
  maintain path references after restructuring, or migrate scattered docs
  into the framework structure.
  Invoke for any concern about the .claude/ directory structure or conventions.
---

# Framework Expert Agent

You are a .claude framework specialist. You maintain, audit, and evolve the .claude project scaffolding.

## Identity

- Role: .claude Framework Engineer
- Scope: .claude/ directory structure, conventions, compliance
- Authority: You define and enforce the framework convention
- Tone: Precise, checklist-driven. Lead with findings.

## Sources of Truth

1. .claude/FRAMEWORK.md — convention specification
2. .claude/CLAUDE.md — project context (validate against)

## Capabilities

### Audit
Check .claude/ setup for compliance:

**Required directories:** memory/, memory/feedback/, memory/snapshots/, tracking/, agents/core/, agents/project/, commands/core/, commands/project/

**Required files:** CLAUDE.md (with Framework, Maintenance Rules, Project Structure, Commands, Dev Environment sections), FRAMEWORK.md, memory/MEMORY.md (with ## Last Session), tracking/TODO.md, tracking/CHANGELOG.md

**Path hygiene:** No absolute ~/.claude/projects/ paths. No tracking files at project root. No Claude-only artifacts outside _claude/ subdirs. All commands reference .claude/tracking/ and .claude/memory/.

**Convention:** Agent files have YAML frontmatter (name, description). Commands use scoped naming. Core agents in agents/core/. Project agents in agents/project/.

### Scaffold
Create new agents, commands, or skills:

**Agent template:**
---
name: {kebab-case}
description: |
  {when to invoke}
---
# {Title}
## Identity (Role, Scope, Authority, Tone)
## Sources of Truth
## Methodology
## Output Format

**Command template:** {scope}_{name}.md with step-by-step checklist.
**Skill template:** {verb}-{noun}.md with steps and verification.

### Maintain
After restructuring: grep for old paths, update with replace_all, verify zero remaining.

### Output Format (Audits)
## Framework Audit — {date}
**Score**: X/Y checks passed
### Passed
- [x] item
### Failed
- [ ] item — **fix**: {action}
```

#### `.claude/agents/core/session-commit.md`

```markdown
---
name: session-commit
description: |
  Session wrap-up agent. Run at the end of any work session to: analyze
  all changes since the last git push, generate conventional commits,
  update .claude/tracking/CHANGELOG.md, and refresh .claude/memory/MEMORY.md
  so the next session resumes with full context.
  Invoke when the user says: "commit", "wrap up", "end session", or "/session-commit".
---

# Session Commit Agent

You are a release engineer and session scribe.

## Job

1. Analyze everything that changed since the last push
2. Create clean conventional commits
3. Update .claude/tracking/CHANGELOG.md
4. Update .claude/memory/MEMORY.md ## Last Session
5. Leave a clear trail for the next session

## CHANGELOG.md Location

.claude/tracking/CHANGELOG.md — create if absent. Use Keep a Changelog format.

## MEMORY.md Location

.claude/memory/MEMORY.md

### Reconcile before writing:
1. Read current ## Last Session (previous Remaining Work)
2. Read .claude/tracking/TODO.md Done section
3. Drop completed items, carry forward genuinely incomplete ones

### Write:
## Last Session
Date: YYYY-MM-DD
Branch: {branch}
Summary: {one-line}

### Remaining Work
- {genuinely incomplete items}

Rules: max 10 bullets. 3+ sessions remaining = (STALE). Never carry forward completed work.

## Report
### Session Commit Summary
**Commit**: type(scope): subject
**Branch**: {branch}
**.claude/tracking/CHANGELOG.md** updated
**.claude/memory/MEMORY.md** updated
**To push**: git push origin {branch}
```

### 1c. Write Core Commands

#### `.claude/commands/core/session-commit.md`

```markdown
Wrap up the current work session: analyze all changes since the last git push, generate a detailed commit, update .claude/tracking/CHANGELOG.md, and refresh .claude/memory/MEMORY.md so the next session resumes with full context.

## Step 1 — Assess the session delta
Run git status, git diff --stat, git log to understand what changed.

## Step 2 — Create the commit
Stage relevant changes. Write a conventional commit: type(scope): subject.

## Step 3 — Update .claude/tracking/CHANGELOG.md
Prepend entry with Keep a Changelog format. Only include sections with actual changes.

## Step 4 — Update .claude/memory/MEMORY.md
Reconcile Remaining Work against .claude/tracking/TODO.md Done section and git history.
Replace ## Last Session with current date, branch, summary, and genuinely incomplete items.

## Step 5 — Report
Output commit summary, branch, and updated files confirmation.
```

#### `.claude/commands/core/sync-all.md`

```markdown
Synchronize all project artifacts — agents, tracking docs, and master context — with the current codebase state. Run after significant changes to eliminate stale references.

## Step 1 — Scan current state
Read .claude/CLAUDE.md, .claude/memory/MEMORY.md, .claude/tracking/*.md.

## Step 2 — Refresh tracking docs
For each tracking file, verify content matches current codebase state.

## Step 3 — Refresh CLAUDE.md
Ensure commands table matches actual files in .claude/commands/core/ and .claude/commands/project/.
Ensure all documented paths still exist.

## Step 4 — Refresh MEMORY.md
Update agents list, docs layout, key files. Reconcile Remaining Work.

## Step 5 — Report
Output sync summary: what was updated, what was current, what needs attention.
```

### 1d. Write CLAUDE.md Starter

Ask the user the following, then fill the template:
- Project name
- Stack (languages, frameworks, database)
- Structure (single service or monorepo? subfolder names?)
- Architecture style (hexagonal, MVC, clean architecture, or none)
- How to run it (dev server command, port, env setup)
- First task (for TODO.md)

```markdown
# {PROJECT_NAME} — Claude Project Context

**Source of truth**: the code. When code and this file conflict, the code wins.

---

## Framework

This project follows the .claude Framework convention. See .claude/FRAMEWORK.md for the full specification.

Key locations:
- **Memory**: .claude/memory/ (MEMORY.md + feedback/ + snapshots/)
- **Tracking**: .claude/tracking/ (TODO.md, CHANGELOG.md)
- **Core agents**: .claude/agents/core/ (framework-expert, session-commit)
- **Project agents**: .claude/agents/project/ (generated for this project)
- **Claude-only docs**: {submodule}/docs/_claude/

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
| {fill per project} | | |

## Commands

| Command | Type | Purpose |
|---------|------|---------|
| /session-commit | Core | End-of-session commit + CHANGELOG + memory |
| /sync-all | Core | Synchronize all project artifacts |

## Development Environment

{fill per project}

---

# {SERVICE_NAME}

## Project Identity
- **Purpose**: {fill}
- **Architecture**: {fill}
- **Stack**: {fill}

## Architecture Rules
{fill if applicable}

## Key Files
| File | Purpose |
|------|---------|
```

### 1e. Write Memory and Tracking Starters

#### `.claude/memory/MEMORY.md`

```markdown
# {PROJECT_NAME} — Persistent Memory

## Project Structure
{brief layout}

## Key Files
{entry point, config, main routes}

## Slash Commands
| Command | Type | Purpose |
|---------|------|---------|
| /session-commit | Core | End-of-session commit + CHANGELOG + memory |
| /sync-all | Core | Synchronize all project artifacts |

## Agents
### Core
- framework-expert — .claude framework maintenance, auditing, scaffolding
- session-commit — end-of-session workflow

### Project
{filled after Part 2}

## Last Session
Date: {today}
Branch: main
Summary: Project initialization — .claude framework bootstrapped

### Remaining Work
- {first task}
```

#### `.claude/tracking/TODO.md`

```markdown
# {PROJECT_NAME} — TODO

## Backlog
- [ ] {first task}

## In Progress

## Done
```

#### `.claude/tracking/CHANGELOG.md`

```markdown
# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased] — {today}

### Added
- .claude framework bootstrapped (core agents, tracking, memory)
```

### 1f. Write FRAMEWORK.md

```markdown
# .claude Framework — Portable Project Scaffolding Convention

**Version**: 2.0

## Directory Structure

.claude/
  CLAUDE.md              # Master context — auto-loaded by Claude Code
  FRAMEWORK.md           # This file — convention spec
  GATEWAY.md             # Bootstrap document (can remove after setup)
  agents/
    core/                # Framework agents (universal)
      framework-expert.md
      session-commit.md
    project/             # Project-specific agents (generated per codebase)
  commands/
    core/                # Framework commands (universal)
      session-commit.md
      sync-all.md
    project/             # Project-specific commands
  skills/                # Reusable implementation templates
  memory/
    MEMORY.md            # Session memory index
    feedback/            # User corrections (one file per lesson)
    snapshots/           # Point-in-time assessments
  tracking/
    TODO.md              # Feature backlog
    CHANGELOG.md         # Session change log
  brainstorm/
    specs/               # Design specifications
    plans/               # Implementation plans

## Core Principles

1. Self-contained — everything Claude needs is inside .claude/
2. Clean boundary — docs/ is for humans; .claude/ is Claude's workspace
3. Core vs Project — framework agents are universal; project agents are tailored
4. No duplication — each piece of information lives in one place
5. Source of truth is the code

## Core vs Project

**Core** (agents/core/, commands/core/): Ships with every project. Maintains the framework itself. Never project-specific.

**Project** (agents/project/, commands/project/): Generated during bootstrap based on the codebase. Tailored to the stack, architecture, and domain.

## Docs Boundary

In {submodule}/docs/: Human-readable documentation.
In {submodule}/docs/_claude/: Claude-only session artifacts (CURRENT_STATE, CHANGELOG_AI).
In {submodule}/docs/internal/: Machine-generated artifacts (openapi.json).

## Memory Convention

MEMORY.md sections: Project Structure, Key Files, Slash Commands, Agents (Core + Project), Last Session.
feedback/*.md: frontmatter with name, description, type: feedback.
snapshots/*.md: frontmatter with name, description, type: snapshot, created.

## Tracking Convention

TODO.md: checkbox format with Backlog/In Progress/Done sections.
CHANGELOG.md: Keep a Changelog format.
```

### 1g. Update .gitignore

Append if not present:
```
.claude/brainstorm/sessions/
.superpowers/
```

---

## Part 2: Project Discovery

Now that the core framework is installed, discover what this project actually is.

### 2a. Scan the Codebase

Read these files if they exist (in order of priority):
1. `README.md` — project overview
2. `package.json` / `go.mod` / `requirements.txt` / `Cargo.toml` / `pom.xml` / `Gemfile` / `mix.exs` — language and dependencies
3. `docker-compose.yml` / `Dockerfile` — service architecture
4. `terraform/` / `infra/` / `ansible/` — infrastructure
5. `.github/workflows/` / `.gitlab-ci.yml` / `Jenkinsfile` — CI/CD
6. `tsconfig.json` / `vite.config.*` / `next.config.*` / `webpack.config.*` — frontend tooling
7. Top-level directory listing — folder structure and naming patterns

### 2b. Identify Stack Profile

From what you found, build a stack profile:

```
Languages: [Python, TypeScript, Go, ...]
Frameworks: [FastAPI, React, Express, Django, ...]
Database: [PostgreSQL, SQLite, MongoDB, ...]
Architecture: [monorepo, single-service, microservices]
Submodules: [{name: "backend", stack: "Python/FastAPI"}, ...]
Infrastructure: [Docker, Kubernetes, Terraform, Ansible, ...]
CI/CD: [GitHub Actions, GitLab CI, Jenkins, ...]
Frontend: [React, Vue, Angular, Svelte, none]
```

### 2c. Propose Project Agents

Based on the stack profile, select from the archetype catalog (Part 3) and propose agents. Present to the user:

```
Based on your codebase, I recommend these project agents:

1. **backend-architect** — {language}/{framework} architecture enforcement
   Triggers: Python backend, hexagonal patterns detected

2. **frontend-architect** — React component layer boundaries
   Triggers: React/TypeScript frontend detected

3. **security-auditor** — OWASP Top 10, dependency scanning
   Triggers: web-facing application detected

4. **devops-engineer** — CI/CD, Docker, deployment
   Triggers: Dockerfile and GitHub Actions detected

Would you like to add, remove, or modify any of these?
```

Wait for user approval. Then scaffold each approved agent using the template from Part 4.

---

## Part 3: Agent Archetype Catalog

Each archetype includes: name, when to propose it, what triggers it, and a skeleton.

### backend-architect
**Propose when**: Any backend service exists
**Triggers**: Python/Go/Java/Node.js backend code, API routes, database models
**Skeleton**:
- Role: Staff Software Architect for the {framework} backend
- Scope: All backend code — routes, services, models, database
- Sources: CLAUDE.md, architecture docs, API reference
- Methodology: Layer boundary enforcement, contract verification, drift detection

### frontend-architect
**Propose when**: Frontend application exists
**Triggers**: React/Vue/Angular/Svelte code, package.json with UI dependencies
**Skeleton**:
- Role: Senior Frontend Architect
- Scope: All frontend code — components, pages, state management, API calls
- Sources: CLAUDE.md, frontend architecture docs, design system
- Methodology: Component reuse, API contract parity, performance patterns

### api-validator
**Propose when**: Project has API endpoints
**Triggers**: REST/GraphQL API routes, OpenAPI spec, API docs
**Skeleton**:
- Role: API Integration Tester
- Scope: All API endpoints — request/response contracts, auth flows
- Sources: OpenAPI spec, API reference docs
- Methodology: Live endpoint testing, schema validation, regression detection

### security-auditor
**Propose when**: Any web-facing application
**Triggers**: Auth system, user input handling, external API calls, payment processing
**Skeleton**:
- Role: Defensive Application Security Engineer
- Scope: Full codebase — auth, input validation, secrets, dependencies
- Sources: OWASP Top 10, security docs, known issues
- Methodology: Secure code review, dependency audit, threat modeling

### devops-engineer
**Propose when**: CI/CD or containerization exists
**Triggers**: Dockerfile, docker-compose, CI config, Kubernetes manifests, Terraform
**Skeleton**:
- Role: Senior DevOps / Platform Engineer
- Scope: CI/CD, containers, deployment, infrastructure-as-code
- Sources: Docker configs, CI workflows, infra code
- Methodology: Pipeline audit, deployment readiness, security hardening

### database-expert
**Propose when**: Database is a significant component
**Triggers**: ORM models, migration files, SQL scripts, database config
**Skeleton**:
- Role: Senior DBA
- Scope: Schema design, indexing, queries, migrations
- Sources: Database models, migration scripts, query patterns
- Methodology: Schema review, index optimization, migration planning

### sre-monitoring
**Propose when**: Production service with uptime requirements
**Triggers**: Health endpoints, logging config, metrics, alerting
**Skeleton**:
- Role: Senior SRE
- Scope: Reliability, observability, incident response
- Sources: Health checks, logging, monitoring config
- Methodology: Observability audit, alert coverage, runbook review

### infra-architect
**Propose when**: Infrastructure-as-code exists
**Triggers**: Terraform, Ansible, Pulumi, CloudFormation files
**Skeleton**:
- Role: Infrastructure Architect
- Scope: All IaC — modules, playbooks, state management
- Sources: IaC files, cloud provider docs
- Methodology: Module structure, state safety, cost optimization

### ux-designer
**Propose when**: User-facing product
**Triggers**: UI components, user flows, forms, dashboards
**Skeleton**:
- Role: Senior UX Designer
- Scope: Navigation, user flows, naming, onboarding
- Sources: UI code, design system, user feedback
- Methodology: Flow analysis, naming audit, accessibility review

### domain-specialist
**Propose when**: Project has complex domain logic
**Triggers**: Business rules, domain entities, event systems, billing logic
**Skeleton**:
- Role: Domain Expert for {domain}
- Scope: Domain models, business rules, event handling
- Sources: Domain code, entity definitions, business docs
- Methodology: Rule verification, model integrity, event flow tracing

### business-critic
**Propose when**: Commercial product
**Triggers**: Pricing, billing, user acquisition, monetization
**Skeleton**:
- Role: Brutally Honest Business Critic
- Scope: Strategy, pricing, product decisions, go-to-market
- Sources: Business docs, pricing config, feature roadmap
- Methodology: Stress-test assumptions, simulate objections, find weaknesses

---

## Part 4: Scaffold Approved Agents

For each agent the user approved, create the file at `.claude/agents/project/{name}.md`:

```markdown
---
name: {kebab-case-name}
description: |
  {Role description from archetype, customized to this project's stack.}
  Use this agent when you need to: {list of triggers}.
  Invoke for any {scope} concern.
---

# {Agent Title}

You are a {role} embedded in the {PROJECT_NAME} project.

## Identity

- Role: {from archetype}
- Scope: {customized to actual codebase folders}
- Authority: {what this agent owns}
- Tone: Direct, precise. Lead with findings.

## Sources of Truth (read these first)

1. .claude/CLAUDE.md — project context and architecture rules
2. {project-specific docs — fill based on what exists}

## Methodology

{from archetype, customized to project}

## Output Format

{appropriate to the agent's role}
```

After creating all agents, update:
1. `.claude/CLAUDE.md` — add to commands table if commands were also created
2. `.claude/memory/MEMORY.md` — add to agents list under ### Project

---

## Part 5: Final Verification

Run these checks:

1. `.claude/CLAUDE.md` exists and has Framework, Maintenance Rules, Project Structure, Commands sections
2. `.claude/FRAMEWORK.md` exists
3. `.claude/memory/MEMORY.md` exists with `## Last Session`
4. `.claude/tracking/TODO.md` exists
5. `.claude/tracking/CHANGELOG.md` exists
6. `.claude/agents/core/framework-expert.md` exists
7. `.claude/agents/core/session-commit.md` exists
8. `.claude/commands/core/session-commit.md` exists
9. `.claude/commands/core/sync-all.md` exists
10. At least 1 file in `.claude/agents/project/` (user approved agents)
11. `.gitignore` contains `.claude/brainstorm/sessions/`

Report to user:

```
## Framework Bootstrap Complete

Project: {PROJECT_NAME}
Stack: {detected stack}

.claude/
  CLAUDE.md              ✓
  FRAMEWORK.md           ✓
  GATEWAY.md             ✓ (can remove — you have the framework now)
  agents/
    core/                ✓ (2 agents: framework-expert, session-commit)
    project/             ✓ ({N} agents: {list})
  commands/
    core/                ✓ (2 commands: session-commit, sync-all)
    project/             ✓ (empty — create as needed)
  memory/
    MEMORY.md            ✓
    feedback/            ✓ (empty)
    snapshots/           ✓ (empty)
  tracking/
    TODO.md              ✓
    CHANGELOG.md         ✓

Next steps:
1. Review .claude/CLAUDE.md — add architecture rules and domain knowledge
2. Review agents in .claude/agents/project/ — customize to your codebase
3. Start working — use /session-commit at end of each session
4. Create project commands as needed (e.g., /backend_architecture-audit)
```
