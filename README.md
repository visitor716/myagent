# MyAgent Skill Source of Truth

This repository is the source of truth for user-managed custom skills.

## Canonical path

- Source of truth: `/home/zhanxp/projects/myagent/skills/`
- Runtime entrypoints: `~/.codex/skills/` and `~/.claude/skills/`

## Rules

1. Edit custom skills only inside `skills/`.
2. Treat `~/.codex/skills/` and `~/.claude/skills/` as runtime mount points, not primary storage.
3. Do not store OMX-managed built-in skills in this repository.
4. Before uninstalling OMX or cleaning runtime directories, verify that custom skills are linked back to this repository.

See [docs/skill-migration-plan.md](/home/zhanxp/projects/myagent/docs/skill-migration-plan.md) for the full migration, linking, uninstall-safety, and recovery process.
