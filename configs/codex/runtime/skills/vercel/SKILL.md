---
name: vercel
description: Imported flat Claude Code skill from vercel.md. Use when the task matches the workflow described below or the user asks for vercel-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/vercel.md -->

# Vercel Skill

Specialized skill for Vercel deployment and management for NeoCD.

## Usage

```
/vercel [command]
```

## Project Configuration

- Config file: `vercel.json`
- Build command: `npm run build`
- Output directory: `dist`
- Framework: Vite

## Common Commands

```bash
# Deploy to preview
vercel

# Deploy to production
vercel --prod

# List deployments
vercel list

# View deployment logs
vercel logs [deployment-url]

# Open project dashboard
vercel open

# Link existing project
vercel link

# Set environment variables
vercel env add VITE_SUPABASE_URL
vercel env pull  # Pull to .env.local
```

## vercel.json Configuration

```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "framework": "vite",
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

## Environment Variables

### Preview vs Production

```bash
# Set for preview deployments
vercel env add VITE_API_URL preview

# Set for production
vercel env add VITE_API_URL production

# Set for all environments
vercel env add VITE_API_URL
```

### Required Variables

| Variable | Environment | Description |
|----------|-------------|-------------|
| `VITE_STORAGE_MODE` | All | local or supabase |
| `VITE_SUPABASE_URL` | All | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | All | Supabase anon key |
| `VITE_OPENAI_API_KEY` | Optional | For AI lyrics |

## Deployment Workflow

### Quick Deploy
```bash
vercel --prod
```

### Full Workflow
```bash
# 1. Build locally first
npm run build

# 2. Test build
npm run preview

# 3. Deploy
vercel --prod
```

## Domain Management

```bash
# Add custom domain
vercel domains add yourdomain.com

# List domains
vercel domains list

# Inspect domain
vercel domains inspect yourdomain.com
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails | Check `npm run build` locally |
| 404 on routes | Add rewrites in vercel.json |
| Env vars missing | Run `vercel env pull` |
| Slow builds | Check dependencies, use caching |

## Examples

```bash
# Deploy preview
/vercel

# Deploy production
/vercel prod

# Check logs
/vercel logs

# List deployments
/vercel list
```