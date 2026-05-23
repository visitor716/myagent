---
name: typecheck
description: Imported flat Claude Code skill from typecheck.md. Use when the task matches the workflow described below or the user asks for typecheck-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/typecheck.md -->

# TypeCheck Skill

Run TypeScript type checking for NeoCD project.

## Usage

```
/typecheck [options]
```

## Primary Command

As per project conventions, always use:
```bash
npx tsc --noEmit
```

This is the required check before completing any code changes.

## Commands

```bash
# Type check (no emit)
npx tsc --noEmit

# Watch mode
npx tsc --noEmit --watch

# Check specific file
npx tsc --noEmit src/components/AudioPlayer.tsx

# Show all errors
npx tsc --noEmit --pretty false

# Generate declaration files
npx tsc --declaration --emitDeclarationOnly
```

## Configuration

- Config file: `tsconfig.json`
- Source: `src/`
- Target: `ES2020`
- Module: `ESNext`
- JSX: `react-jsx`

## Common Type Errors & Fixes

### Module Import Errors
```typescript
// ❌ Error: Cannot find module '@/components/X'
import X from '@/components/X'

// ✅ Fix: Check tsconfig.json paths
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

### Null/Undefined Errors
```typescript
// ❌ Error: Object is possibly 'null'
const value = obj.property

// ✅ Fix: Optional chaining
const value = obj?.property

// ✅ Fix: Non-null assertion (when sure)
const value = obj!.property
```

### Type Mismatches
```typescript
// ❌ Error: Type 'string' is not assignable to type 'number'
const count: number = '123'

// ✅ Fix: Convert type
const count: number = parseInt('123')
```

### React Props Errors
```typescript
// ❌ Error: Property 'onClick' is missing
<Button label="Click" />

// ✅ Fix: Add required prop
<Button label="Click" onClick={() => {}} />

// ✅ Fix: Make prop optional
interface Props {
  onClick?: () => void
}
```

## Type Checking Workflow

When completing code changes:

1. **Run type check**
   ```bash
   npx tsc --noEmit
   ```

2. **If errors exist**:
   - Analyze the FIRST error
   - Fix with MINIMAL code changes
   - Re-run type check

3. **Repeat until clean**

## Examples

```bash
# Standard type check
/typecheck

# Watch for changes
/typecheck --watch

# Verbose output
/typecheck --verbose
```

## Integration with Editor

For VS Code:
- Install TypeScript extension
- Enable "TypeScript > Preferences: Import Module Specifier" → "relative"
- Use `Ctrl+Shift+M` for error list

## Pre-commit Integration

Add to `.husky/pre-commit`:
```bash
npx tsc --noEmit || (echo "Type errors found" && exit 1)
```