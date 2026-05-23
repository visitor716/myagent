---
name: review
description: Imported flat Claude Code skill from review.md. Use when the task matches the workflow described below or the user asks for review-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/review.md -->

# Review Skill

Perform thorough code review for NeoCD project.

## Usage

```
/review [file]      # Review specific file
/review diff        # Review current changes
/review pr [number] # Review PR
```

## Review Checklist

### Code Quality

- [ ] Code follows project conventions (PascalCase, camelCase)
- [ ] Functions are < 80 lines
- [ ] Components are < 250 lines
- [ ] Pages are < 400 lines
- [ ] No unused imports or variables
- [ ] TypeScript types are properly defined

### React Best Practices

- [ ] Components are functional with hooks
- [ ] Single responsibility principle
- [ ] Proper use of useEffect dependencies
- [ ] No memory leaks (cleanup in useEffect)
- [ ] Proper key usage in lists

### Security

- [ ] No hardcoded credentials
- [ ] User input validated with Zod
- [ ] No XSS vulnerabilities
- [ ] SQL injection prevention (use Supabase client)
- [ ] Proper authentication checks

### Performance

- [ ] No unnecessary re-renders
- [ ] Proper memoization (useMemo, useCallback)
- [ ] Lazy loading where appropriate
- [ ] IndexedDB queries optimized

### Testing

- [ ] Tests cover critical paths
- [ ] Tests are in `/tests` directory
- [ ] Mock external dependencies

## Review Output Format

```markdown
## Code Review Summary

### ✅ Approved
- Good: [list positive aspects]

### ⚠️ Suggestions
- [suggestion 1]
- [suggestion 2]

### 🚫 Issues
- [issue 1] (file:line)
- [issue 2] (file:line)

### 📝 Questions
- [question 1]
```

## Common Issues to Watch

| Category | Issue | Fix |
|----------|-------|-----|
| Types | `any` type | Define proper interface |
| React | Missing deps | Add to useEffect array |
| Security | `dangerouslySetInnerHTML` | Sanitize input |
| Performance | Inline object creation | Move outside render |
| Style | Inline styles | Use Tailwind classes |

## Examples

```bash
# Review staged changes
/review diff

# Review specific file
/review src/components/AudioPlayer.tsx

# Review last commit
/review commit HEAD
```