---
name: vitest
description: Imported flat Claude Code skill from vitest.md. Use when the task matches the workflow described below or the user asks for vitest-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/vitest.md -->

# Vitest Skill

Specialized skill for Vitest testing framework used in NeoCD project.

## Usage

```
/vitest [command] [options]
```

## Configuration

- Config file: `vitest.config.ts`
- Setup file: `tests/setup.ts`
- Coverage: v8 coverage provider

## Commands

### Run Tests

```bash
# Run all tests once
vitest run

# Run specific file
vitest run tests/unit/AudioPlayer.test.tsx

# Run with pattern
vitest run -t "should render"

# Watch mode
vitest watch

# UI mode (visual test runner)
vitest --ui
```

### Coverage

```bash
# Generate coverage report
vitest run --coverage

# Coverage with specific provider
vitest run --coverage.provider=v8
```

## Debugging Tests

```bash
# Run with Node debugger
vitest run --inspect

# Run single test with logs
vitest run tests/unit/example.test.ts --reporter=verbose
```

## Best Practices for NeoCD

1. **Mock IndexedDB** for storage tests
2. **Mock Web Audio API** for player tests
3. **Use MSW** for Supabase API mocking
4. **Clean up after each test** with `afterEach`

## Example Test Patterns

```typescript
// Component test
import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'

describe('Component', () => {
  it('should handle click', async () => {
    const onClick = vi.fn()
    render(<Button onClick={onClick} />)

    await fireEvent.click(screen.getByRole('button'))

    expect(onClick).toHaveBeenCalledOnce()
  })
})

// Hook test
import { renderHook, act } from '@testing-library/react'
import { describe, it, expect } from 'vitest'

describe('useHook', () => {
  it('should return value', () => {
    const { result } = renderHook(() => useCustomHook())

    expect(result.current).toBeDefined()
  })
})
```

## Common Issues

| Issue | Solution |
|-------|----------|
| `toBeInTheDocument is not a function` | Import from `@testing-library/jest-dom` |
| `Cannot find module @/...` | Check `vitest.config.ts` alias config |
| IndexedDB errors | Mock in `tests/setup.ts` |