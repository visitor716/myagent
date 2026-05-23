---
name: test
description: Imported flat Claude Code skill from test.md. Use when the task matches the workflow described below or the user asks for test-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/test.md -->

# Test Skill

Run and manage tests for the NeoCD project.

## Usage

```
/test [options] [pattern]
```

## Instructions

When invoked, run the appropriate test command based on the context:

## Test Commands

| Command | Description |
|---------|-------------|
| `npm run test` | Run all unit tests |
| `npm run test:watch` | Watch mode for development |
| `npm run test:coverage` | Generate coverage report |
| `npm run test:e2e` | Run E2E tests with Cucumber |
| `npm run test:db` | Test Supabase connection |

## Test File Location

- Unit tests: `/tests/unit/*.test.tsx`
- E2E tests: `/tests/features/*.feature`

## Examples

```bash
# Run all tests
/test

# Run specific test file
/test AudioPlayer

# Run tests in watch mode
/test --watch

# Run with coverage
/test --coverage

# Run E2E tests
/test --e2e

# Run tests matching pattern
/test --pattern "upload"
```

## Writing Tests

When writing tests for this project:

1. **Place tests in `/tests` directory** - NOT in `src/`
2. **Naming convention**: `*.test.tsx` or `*.test.ts`
3. **Use Vitest** with React Testing Library
4. **Follow AAA pattern**: Arrange, Act, Assert

## Test Structure Example

```typescript
// tests/unit/AudioPlayer.test.tsx
import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import { AudioPlayer } from '@/components/AudioPlayer'

describe('AudioPlayer', () => {
  it('should render play button', () => {
    render(<AudioPlayer />)
    expect(screen.getByRole('button', { name: /play/i }))
  })
})
```

## Coverage Thresholds

Aim for:
- Statements: 70%+
- Branches: 60%+
- Functions: 70%+
- Lines: 70%+