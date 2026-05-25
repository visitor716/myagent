# MyAgent AI Work Archive

This repository is the source of truth for everything worth preserving from
learning AI and using AI: custom skills, workflow notes, local automation,
agent configuration, browser/proxy routines, and reusable operating memory.

It is not only a skill repository. Skills are one storage format inside the
larger archive of AI-use experience that should be reusable across tools,
machines, projects, and future agent sessions.

## Canonical paths

- Project source of truth: `/home/zhanxp/projects/myagent/`
- Skill source of truth: `/home/zhanxp/projects/myagent/skills/`
- Runtime entrypoints: `~/.codex/skills/` and `~/.claude/skills/`

## Rules

1. Edit custom skills only inside `skills/`.
2. Treat `~/.codex/skills/` and `~/.claude/skills/` as runtime mount points, not primary storage.
3. Do not store OMX-managed built-in skills in this repository.
4. Before uninstalling OMX or cleaning runtime directories, verify that custom skills are linked back to this repository.

## 配置管理

本项目同时管理 Claude Code 和 Codex 的配置模板：

- **`configs/claude code/settings.json`** — Claude Code 配置模板（已脱敏）
- **`configs/codex/config.toml`** — Codex 配置模板
- **`configs/codex/bash_aliases.full-auto.sh`** — Codex 全自动 bash 入口模板
- **`configs/sync.sh`** — 配置同步脚本（支持 backup / restore / codex-full-auto / validate）

详见 [configs/README.md](configs/README.md)。

常用复用命令：

```bash
bash configs/sync.sh codex-full-auto
```

该命令会把 `code x` / `codex` 默认入口安装为 Codex 无审批、无沙箱模式，并保留
`cfa` 作为较安全的 `--full-auto` 入口。

See [docs/skill-migration-plan.md](/home/zhanxp/projects/myagent/docs/skill-migration-plan.md) for the full migration, linking, uninstall-safety, and recovery process.
