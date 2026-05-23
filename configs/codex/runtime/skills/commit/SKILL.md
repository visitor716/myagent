---
name: commit
description: Imported flat Claude Code skill from commit.md. Use when the task matches the workflow described below or the user asks for commit-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/commit.md -->

# Commit Skill

Generate a well-structured git commit following the project's conventions.

## Usage

```
/commit [message]
```

## Instructions

When invoked, follow these steps:

1. **Check git status** - Run `git status` to see all changes
2. **Review changes** - Run `git diff` to understand what was modified
3. **Stage files** - Only stage relevant files (avoid .env, credentials, etc.)
4. **Generate commit message** following these conventions:
   - Use conventional commits format: `type(scope): description`
   - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
   - Keep the first line under 72 characters
   - Use imperative mood ("add feature" not "added feature")

## Commit Types for NeoCD

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(player): add shuffle mode` |
| `fix` | Bug fix | `fix(upload): resolve CORS issue` |
| `docs` | Documentation | `docs: update README` |
| `style` | Code style | `style: format with prettier` |
| `refactor` | Code refactoring | `refactor(auth): simplify login flow` |
| `test` | Tests | `test(audio): add unit tests for player` |
| `chore` | Maintenance | `chore: update dependencies` |
| `perf` | Performance | `perf(cache): optimize IndexedDB queries` |

## Examples

```bash
# Without message - auto-generate
/commit

# With specific message
/commit "feat(player): add volume control"

# Amend last commit (with confirmation)
/commit --amend
```

## Pre-commit Checklist

- [ ] Run `npx tsc --noEmit` to check types
- [ ] Ensure no sensitive files are staged
- [ ] Commit message follows convention
- [ ] Changes are atomic (one logical change per commit)

## Dirty Worktree / Partial Commit Notes

- If the repository already has unrelated modified or untracked files, do not stage everything.
- Use path-limited `git diff -- <files>` and `git add <files>` for files that fully belong to the requested commit.
- If a relevant file also contains unrelated hunks, use `git add -p <file>` to stage only the requested hunks, then verify with `git diff --cached`.
- Before committing, run `git diff --cached --check` and the narrowest relevant test command for the staged change.
- After committing, run `git status --short` and mention any remaining unrelated changes that were intentionally left uncommitted.