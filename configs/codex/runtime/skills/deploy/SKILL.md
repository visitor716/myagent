---
name: deploy
description: Imported flat Claude Code skill from deploy.md. Use when the task matches the workflow described below or the user asks for deploy-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/deploy.md -->

# Deploy Skill

Handle deployment workflow for NeoCD project on Vercel.

## Usage

```
/deploy [type]      # Deploy with version bump
/deploy preview     # Preview deployment
/deploy status      # Check deployment status
```

## Deployment Commands

| Command | Description | Version Change |
|---------|-------------|----------------|
| `npm run deploy:patch` | Patch release | 1.0.0 → 1.0.1 |
| `npm run deploy:minor` | Minor release | 1.0.0 → 1.1.0 |
| `npm run deploy:major` | Major release | 1.0.0 → 2.0.0 |
| `npm run deploy:prod` | Production deploy | No version change |

## Pre-Deployment Checklist

- [ ] All tests pass (`npm run test`)
- [ ] TypeScript compiles (`npx tsc --noEmit`)
- [ ] Build succeeds (`npm run build`)
- [ ] No console errors
- [ ] Environment variables set in Vercel
- [ ] `.env.local` NOT committed

## Deployment Process

1. **Version Bump**
   ```bash
   npm run version:patch  # or minor/major
   ```

2. **Build & Test**
   ```bash
   npm run build
   npm run test
   ```

3. **Deploy**
   ```bash
   npm run deploy:prod
   ```

## Environment Variables (Vercel)

Required variables in Vercel dashboard:

```bash
VITE_STORAGE_MODE=local
VITE_SUPABASE_URL=https://xxx.supabase.co
VITE_SUPABASE_ANON_KEY=xxx
```

## Rollback

If deployment fails:

```bash
# List deployments
vercel list

# Rollback to previous
vercel rollback [deployment-url]
```

## Examples

```bash
# Patch release (bug fixes)
/deploy patch

# Minor release (new features)
/deploy minor

# Major release (breaking changes)
/deploy major

# Quick production deploy
/deploy prod

# Check status
/deploy status
```

## Semantic Versioning

| Version | When to use |
|---------|-------------|
| Patch | Bug fixes, small tweaks |
| Minor | New features, backward compatible |
| Major | Breaking changes |

## Post-Deployment

- Verify site loads correctly
- Test critical user flows
- Check Vercel logs for errors
- Monitor performance metrics