# Skill Migration Status

## Canonical Source

- `/home/zhanxp/projects/myagent/skills/skills-download/` for downloaded custom skills
- `/home/zhanxp/projects/myagent/skills/skills-local/` for local/rebuilt custom skills

The old flat `/home/zhanxp/projects/myagent/skills/<skill-name>` layout is no longer canonical. Runtime links should point at one of the categorized directories above.

## Migrated To Repo

### Downloaded custom skills

- `agent-usage-monitor`
- `ai-slop-cleaner`
- `claude-to-im`
- `code-review`
- `coding-standards`
- `deploy-to-vercel`
- `find-docs`
- `find-skills`
- `image-renamer`
- `security-review`
- `vercel-composition-patterns`
- `vercel-react-best-practices`
- `vercel-react-native-skills`
- `web-design-guidelines`
- `wx-cli`

### Local/rebuilt custom skills

- `cc-connect-bot-setup`
- `create-telegram-bot-bridge`
- `daily-report-table`
- `neocd-change-workflow`
- `sync-shared-skills`
- `wsl-windows-chrome`

## Metadata

Every repo-managed custom skill now has a `.skill-source.json` file with:

- `source_of_truth` pointing at the categorized repo path
- `runtime_targets` listing the corresponding Codex/Claude runtime symlinks when present or intended
- `sync_policy: symlink-preferred`

## Runtime Alias Needed

- `Claude-to-IM-skill` should remain as a compatibility symlink to `skills/skills-download/claude-to-im` in both `~/.codex/skills` and `~/.claude/skills`.

## Runtime Issues Found

- `~/.codex/skills/Claude-to-IM-skill` was originally an empty directory, not a trustworthy source.
- `create-telegram-bot-bridge` original source content was missing from runtime paths and had to be rebuilt from local Codex logs and current `claude-to-im` config contract.
- After the repo was reorganized into `skills-download/` and `skills-local/`, many runtime symlinks in `~/.codex/skills` and `~/.claude/skills` still pointed at the old flat `skills/<skill-name>` paths. These links were retargeted to the categorized repo paths.
- `~/.claude/skills/playwright-cli` pointed at a missing `~/.codex/skills/playwright-cli` source and no repo/runtime source was found, so the dead symlink was removed.

## Not Migrated

- OMX built-in skills under `~/.codex/skills/` were intentionally left out of this repo.
- `~/.claude/skills` loose prompt files such as `audio.md`, `commit.md`, `deploy.md`, `lint.md`, `pr.md`, `review.md`, `test.md`, `typecheck.md`, `vercel.md`, and `vitest.md` were not treated as custom skill directories.

## Follow-up Rule

- Only skill directories backed by repo content should be linked into runtime skill paths.
- Broken runtime links should be repaired when a categorized repo source exists; otherwise remove the dead link after confirming no real source exists.
- New custom skills added under `skills/skills-download/` or `skills/skills-local/` should include `.skill-source.json` before being linked into runtime skill paths.
