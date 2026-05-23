---
name: pr
description: Imported flat Claude Code skill from pr.md. Use when the task matches the workflow described below or the user asks for pr-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/pr.md -->

# PR Skill

Create and manage Pull Requests for NeoCD project.

## Usage

```
/pr [number]      # View PR details
/pr create        # Create new PR
/pr review        # Review current PR
```

## Instructions

### Creating a PR

1. **Ensure branch is pushed**
   ```bash
   git push -u origin <branch-name>
   ```

2. **Create PR with gh CLI**
   ```bash
   gh pr create --title "feat: description" --body "..."
   ```

3. **PR Template Structure**
   ```markdown
   ## Summary
   - Bullet point summary of changes

   ## Test plan
   - [ ] Test item 1
   - [ ] Test item 2
   ```

### PR Naming Convention

Follow conventional commits:
- `feat(player): add shuffle mode`
- `fix(upload): resolve CORS issue`
- `refactor(auth): simplify login flow`

### PR Checklist

- [ ] Branch is up to date with main
- [ ] All tests pass (`npm run test`)
- [ ] TypeScript compiles (`npx tsc --noEmit`)
- [ ] No console errors in browser
- [ ] PR description is clear
- [ ] Linked to issue (if applicable)

## Examples

```bash
# Create PR from current branch
/pr create

# View PR #123
/pr 123

# Review PR #123
/pr review 123

# Check PR status
/pr status
```

## PR Size Guidelines

| Size | Lines Changed | Recommendation |
|------|--------------|----------------|
| XS | < 50 | Quick review |
| S | 50-150 | Normal review |
| M | 150-500 | Thorough review |
| L | 500-1000 | Consider splitting |
| XL | > 1000 | Must split |

## Merge Strategy

- **Squash and merge** for feature branches
- **Rebase and merge** for clean history
- **Create merge commit** for release branches