# Repository Guidelines

## Project Structure & Module Organization

This repository preserves reusable assets from day-to-day AI work and synchronizes them into other projects or runtime tool directories. It is the source of truth for user-managed agent skills, workflow notes, helper scripts, and local agent configuration. Keep custom skills under `skills/`: downloaded skills live in `skills/skills-download/`, local/private workflow skills live in `skills/skills-local/`, and each skill should include `SKILL.md` plus `.skill-source.json`. Configuration templates live in `configs/`, split between `configs/claude-code/` and `configs/codex/`. Operational helper scripts live in `scripts/`; samples and ad hoc tests are under `scripts/Test/`. Longer design and migration notes belong in `docs/`.

## Build, Test, and Development Commands

There is no single app build step. Use targeted validation:

```bash
bash configs/sync.sh validate
```

Validates tracked Claude Code and Codex config templates.

```bash
bash -n configs/sync.sh
find scripts -name '*.py' -print0 | xargs -0 python -m py_compile
```

Checks shell syntax and Python syntax for helper scripts.

```bash
bash configs/sync.sh backup
bash configs/sync.sh restore
```

Backs up runtime configs into this repo or restores repo templates to runtime locations. Review and redact secrets before committing backups.

## Coding Style & Naming Conventions

Use Markdown for documentation and keep instructions direct. Shell scripts should use `set -euo pipefail`, quote variables, and keep idempotent operations safe to re-run. Python scripts should prefer clear functions, explicit paths, and standard-library dependencies unless a skill documents otherwise. Skill directories use lowercase, hyphenated names such as `daily-report-table` or `cc-switch-skill`.

## Testing Guidelines

Add focused tests or sample inputs near the script or skill they cover. For Python helpers, use `scripts/Test/` or a nearby `*Test.py` file when matching existing patterns. Always run `configs/sync.sh validate` after config changes and `python -m py_compile` on changed Python files. For skill changes, verify the changed `SKILL.md` is usable from a clean checkout and `.skill-source.json` remains present.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commits, for example `feat(skills): ...`, `fix(daily-report): ...`, `docs(skills): ...`, and `chore(deps): ...`. Keep subjects imperative and scoped. Pull requests should explain the intent, list touched directories, include validation commands run, and call out any runtime config or secret-handling impact. Include screenshots only for UI/browser automation changes.

## Security & Configuration Tips

Never commit real API keys, tokens, or machine-local secrets. Use `.env.example`, `${VAR_NAME}` placeholders, and ignored local files such as `configs/claude-code/.env` or `configs/codex/config.local.toml`. Treat `~/.codex/skills/` and `~/.claude/skills/` as runtime mount points, not primary storage.

## Codex Runtime Preferences

The user's preferred Codex posture on this trusted machine is high-autonomy:
keep `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`
unless the user explicitly asks to reduce privileges. Within higher-priority
safety rules, proceed with reversible local configuration and verification work
without asking for confirmation.

For browser automation from WSL, use the `wsl-windows-chrome` skill and its
dedicated Windows Chrome/Edge automation profile. Do not add or use
Chrome/Browser MCP for normal browser tasks unless the user explicitly asks for
MCP. If the dedicated Windows CDP endpoint is unavailable, report diagnostics
instead of falling back to a fresh WSL/Linux browser.

Long-term Codex memory lives under `docs/agent-memory/`. Update
`open-loops.md` for paused follow-ups, `decisions.md` for durable choices, and
`codex-operating-memory.md` for stable preferences. Keep these files free of
secrets.
