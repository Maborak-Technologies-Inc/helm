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
      argocd-architect.md
      devops.md
      helm-architect.md
      kubernetes-architect.md
      security-auditor.md
      sre.md
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

## Memory Convention

MEMORY.md sections: Project Structure, Key Files, Slash Commands, Agents (Core + Project), Last Session.
feedback/*.md: frontmatter with name, description, type: feedback.
snapshots/*.md: frontmatter with name, description, type: snapshot, created.

## Tracking Convention

TODO.md: checkbox format with Backlog/In Progress/Done sections.
CHANGELOG.md: Keep a Changelog format.
