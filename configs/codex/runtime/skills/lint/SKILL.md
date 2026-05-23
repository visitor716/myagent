---
name: lint
description: Imported flat Claude Code skill from lint.md. Use when the task matches the workflow described below or the user asks for lint-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/lint.md -->

# Lint Skill

Run ESLint and code quality checks for NeoCD project.

## Usage

```
/lint [options] [files]
```

## Configuration

- ESLint config: `eslint.config.js` or `.eslintrc.cjs`
- Prettier config: `.prettierrc`
- Editor config: `.editorconfig`

## Commands

```bash
# Run ESLint on all files
npm run lint

# Run with auto-fix
npm run lint -- --fix

# Check specific files
npx eslint src/components/AudioPlayer.tsx

# Run Prettier
npx prettier --write "src/**/*.{ts,tsx}"

# Check formatting without writing
npx prettier --check "src/**/*.{ts,tsx}"
```

## ESLint Rules

Common rules for this project:

| Rule | Setting | Description |
|------|---------|-------------|
| `@typescript-eslint/no-unused-vars` | error | No unused variables |
| `@typescript-eslint/no-explicit-any` | warn | Avoid `any` type |
| `react-hooks/exhaustive-deps` | error | Hook dependencies |
| `react/jsx-key` | error | Key in lists |

## Prettier Settings

Based on project conventions:
- Tab width: 2 spaces
- Single quotes
- Trailing commas
- No semicolons (optional)

## Common Issues & Fixes

### Unused Variables
```typescript
// ❌ Error
const unused = 'value'

// ✅ Fix
const _unused = 'value' // prefix with underscore
```

### Missing Dependencies
```typescript
// ❌ Error
useEffect(() => {
  doSomething(value)
}, [])

// ✅ Fix
useEffect(() => {
  doSomething(value)
}, [value])
```

### Any Type
```typescript
// ❌ Error
function process(data: any) { }

// ✅ Fix
interface Data { field: string }
function process(data: Data) { }
```

## Pre-commit Hook

Run lint before each commit:
```bash
# Add to package.json scripts
"lint:fix": "eslint src --fix && prettier --write src"
```

## Examples

```bash
# Check all files
/lint

# Auto-fix issues
/lint --fix

# Check specific directory
/lint src/components/

# Format with Prettier
/lint format
```