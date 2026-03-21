Wrap up the current work session: analyze all changes since the last git push, generate a detailed commit for any uncommitted work, and update context so the next session resumes smoothly.

## Step 1 — Assess the session delta

Run in parallel:
```bash
git log origin/$(git branch --show-current)..HEAD --oneline
git diff origin/$(git branch --show-current)...HEAD --stat
git status --short
```

- If no commits and no working tree changes: report "Nothing to commit" and stop.
- If there are unpushed commits only (no working tree changes): skip to Step 3.
- If there are working tree changes (staged or unstaged): proceed to Step 2.

## Step 2 — Stage and commit uncommitted changes

Read the key changed files to understand what was done.

Stage tracked modifications:
```bash
git add -u
```

Stage new files individually if they're part of the session's work (templates, values, agents, commands, skills). Never `git add .`.

Verify staged set:
```bash
git diff --cached --stat
```

Write a conventional commit:
- Format: `<type>(<scope>): <imperative subject>`
- Body: bullet points — what changed and why, with file references
- Footer: `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>`

Type guide: `feat` (new chart feature), `fix` (template fix), `refactor` (chart restructure), `chore` (tooling/agents/commands), `docs` (docs only)
Scope guide: `chart`, `zabbix`, `argocd`, `ci`, `tooling`, or omit for cross-cutting

Commit using HEREDOC:
```bash
git commit -m "$(cat <<'EOF'
type(scope): subject line here

- Bullet explaining change 1
- Bullet explaining change 2

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

If a pre-commit hook fails: fix the issue, re-stage, create a NEW commit (never --amend, never --no-verify).

## Step 3 — Report to user

Output:
```
### Session Commit Summary

**Commit**: `type(scope): subject`
**Files**: N changed, M insertions, K deletions
**Branch**: <branch> (not pushed)

**To push**: git push origin <branch>
```
