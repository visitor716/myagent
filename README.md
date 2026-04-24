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

## 配置管理

本项目同时管理 Claude Code 和 Codex 的配置模板：

- **`configs/claude-code/settings.json`** — Claude Code 配置模板（已脱敏）
- **`configs/codex/config.toml`** — Codex 配置模板
- **`configs/sync.sh`** — 配置同步脚本（支持 backup / restore / validate）

详见 [configs/README.md](configs/README.md)。

See [docs/skill-migration-plan.md](/home/zhanxp/projects/myagent/docs/skill-migration-plan.md) for the full migration, linking, uninstall-safety, and recovery process.
