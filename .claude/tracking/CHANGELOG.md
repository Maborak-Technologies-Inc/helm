# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased] — 2026-03-20

### Added
- .claude framework v2.0 bootstrapped (core/project agent split, memory, tracking, brainstorm directories)
- `.claude/CLAUDE.md` — framework-aware project context
- `.claude/FRAMEWORK.md` — convention specification
- `.claude/agents/core/framework-expert.md` — framework auditing and scaffolding
- `.claude/agents/core/session-commit.md` — session wrap-up agent
- `.claude/commands/core/session-commit.md` — session commit command (moved from flat)
- `.claude/commands/core/sync-all.md` — sync-all command (moved from flat, paths updated)
- `.claude/memory/MEMORY.md` — persistent session memory
- `.claude/tracking/TODO.md` — feature backlog
- `.claude/tracking/CHANGELOG.md` — this file

### Changed
- Moved 6 project agents from `.claude/agents/` → `.claude/agents/project/`
- Moved 9 project commands from `.claude/commands/` → `.claude/commands/project/`
- Updated sync-all agent inventory paths to reflect new directory structure
