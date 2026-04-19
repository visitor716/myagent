# Skill Migration Status

## Canonical Source

- `/home/zhanxp/projects/myagent/skills/`

## Migrated To Repo

- `claude-to-im`
- `create-telegram-bot-bridge`
- `deploy-to-vercel`
- `web-design-guidelines`
- `vercel-composition-patterns`
- `vercel-react-best-practices`
- `vercel-react-native-skills`

## Runtime Alias Needed

- `Claude-to-IM-skill` should remain as a compatibility symlink to `skills/claude-to-im`

## Runtime Issues Found

- `~/.codex/skills/Claude-to-IM-skill` was an empty directory, not a trustworthy source
- `create-telegram-bot-bridge` original source content was missing from runtime paths and had to be rebuilt from local Codex logs and current `claude-to-im` config contract

## Not Migrated

- OMX built-in skills under `~/.codex/skills/` were intentionally left out of this repo
- `~/.claude/skills` loose prompt files such as `audio.md`, `commit.md`, `deploy.md`, `lint.md`, `pr.md`, `review.md`, `test.md`, `typecheck.md`, `vercel.md`, and `vitest.md` were not treated as custom skill directories

## Follow-up Rule

- Only skill directories backed by repo content should be linked into runtime skill paths
- Broken runtime links should be repaired or removed after confirming whether a real source still exists
