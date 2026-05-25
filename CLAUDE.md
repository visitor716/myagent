# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Source-of-truth repository for everything worth preserving from learning AI and
using AI: custom agent skills, configuration templates, utility scripts,
workflow notes, browser/proxy routines, and durable operating memory. This is
not a traditional software project — there is no top-level build, lint, or test
suite.

## Repo structure

```
skills/skills-local/     # User-created custom skills (the primary working area)
skills/skills-download/  # Downloaded/managed skills (OMX-managed, less frequently edited)
configs/                 # Claude Code + Codex config templates, plus sync.sh
scripts/                 # Miscellaneous Windows/WSL utility scripts
docs/                    # Migration plans and status docs
```

## Skill anatomy

Each skill in `skills-local/` follows this layout:

```
<skill-name>/
├── SKILL.md              # Skill definition — main file to edit for behavior changes
├── .skill-source.json    # Metadata (source owner, runtime targets, sync policy)
├── agents/openai.yaml    # Optional: OpenAI-compatible agent configuration
├── scripts/              # Implementation scripts the skill invokes
├── references/           # Optional reference docs loaded by the skill
└── tests/                # Optional test files (only daily-report-table currently)
```

When editing a skill, `SKILL.md` is the entry point. Scripts are in `scripts/`.

## Config management

```bash
bash configs/sync.sh validate          # Validate config formats
bash configs/sync.sh restore           # Copy templates → runtime (~/.claude/, ~/.codex/)
bash configs/sync.sh backup            # Copy runtime → templates (sanitize secrets after!)
bash configs/sync.sh codex-full-auto   # Install Codex no-approval, no-sandbox aliases
```

Config templates are sanitized — real secrets live in env vars, never committed.

## Selected local skills

- **cc-switch-skill** — Switch Claude Code between AI providers (Baidu Qianfan, etc.). `scripts/cc-switch-run.sh` is the main entry.
- **daily-report-table** — Convert Chinese daily report text into fixed table rows. Has its own `pyproject.toml` and `tests/`. Run tests: `cd skills/skills-local/daily-report-table && pytest`.
- **wsl-windows-chrome** — Attach from WSL to a Windows Chrome/Edge browser with a fixed CDP port. Scripts manage CDP relay lifecycle.
- **cc-connect-bot-setup** — Set up Claude Code as an IM bot bridge.
- **clash-proxy** — Manage Clash proxy region policies from WSL.
- **create-telegram-bot-bridge** — Create/rotate Telegram bots for Claude-to-IM.
- **worktree-execution-acceptance** — Collect evidence from git worktree execution.
- **telegram-input-flow** — Telegram input processing workflow.
- **neocd-change-workflow** — Neo CD change management workflow.

## Key rules

1. Edit custom skills only inside `skills/skills-local/`.
2. Runtime directories (`~/.codex/skills/`, `~/.claude/skills/`) are mount points, not primary storage.
3. Never commit real API keys or tokens. Use `${VAR_NAME}` placeholders in configs.
4. After `configs/sync.sh backup`, always check for and redact secrets before committing.
5. Skill directory names are lowercase kebab-case.
