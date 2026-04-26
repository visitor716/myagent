---
name: cc-switch-skill
description: Diagnose and operate cc-switch from WSL or Windows-backed homes. Use when the user mentions cc-switch, providers, models, APIs, provider-count mismatches between WSL CLI and the Windows cc-switch app, or wants to list, switch, add, edit, or validate cc-switch providers.
---

# CC Switch Skill

Use this skill to manage `cc-switch`, especially from WSL where Linux and Windows may have separate `~/.cc-switch` databases.

Canonical paths:

- WSL database: `~/.cc-switch/cc-switch.db`
- Windows database from WSL: `/mnt/c/Users/<WindowsUser>/.cc-switch/cc-switch.db`
- Skill source of truth: `/home/zhanxp/projects/myagent/skills/skills-local/cc-switch-skill`

## Safety Rules

- Treat provider secrets as sensitive. Prefer `provider list`, `provider current`, and `config validate`; do not print full config blobs unless the user explicitly asks.
- Distinguish **providers/APIs** from **models**. `provider list` and `config validate` count providers, not the model names attached to a provider.
- If the user says “cc-switch 软件”, “Windows app”, “GUI”, or reports counts seen in the Windows app, assume the Windows database is the likely source of truth until proven otherwise.
- Before editing providers on an existing database, create a backup with `config backup` or copy the target `cc-switch.db`.

## Default Workflow

1. Run `bash scripts/cc-switch-run.sh doctor` first.
2. If the Windows app is the source of truth, use `--windows`.
3. If the user explicitly wants the WSL-local CLI database, use `--wsl`.
4. If the target is unclear, use `--auto`; it prefers the home with the larger provider count.
5. After modifications, rerun `config validate` and `provider current` against the same target home.

## Quick Start

```bash
# Compare WSL and Windows cc-switch databases and print the recommended target
bash scripts/cc-switch-run.sh doctor

# List providers from the Windows-backed cc-switch database while running in WSL
bash scripts/cc-switch-run.sh --windows provider list

# Validate provider counts for the Windows-backed database
bash scripts/cc-switch-run.sh --windows config validate

# List only Codex providers from the Windows-backed database
bash scripts/cc-switch-run.sh --windows --app codex provider list

# Show the current Claude provider from the Windows-backed database
bash scripts/cc-switch-run.sh --windows --app claude provider current

# Switch a Windows-backed provider
bash scripts/cc-switch-run.sh --windows --app codex provider switch <provider-id>

# Add a provider to the WSL-local database explicitly
bash scripts/cc-switch-run.sh --wsl --app codex provider add
```

## Mismatch Handling

When CLI and GUI disagree, the common cause is that they are reading different homes:

- `cc-switch` in WSL defaults to `/home/<user>/.cc-switch`
- the Windows app often uses `C:\Users\<user>\.cc-switch`

If raw `cc-switch provider list` says `No providers found` but the Windows app clearly shows providers, rerun the same command through this skill with `--windows` or `doctor`.

## Claude Live Config Notes

- Claude live config is not only `~/.claude/`; `cc-switch` may also read or sync the root-level `~/.claude.json`.
- In a WSL + Windows setup, the useful pair is often:
  - Windows source: `/mnt/c/Users/<WindowsUser>/.claude.json`
  - WSL live file: `~/.claude.json`
- If `provider switch` warns that Claude local live config was not detected, rerun the switch with `-v` and inspect whether `cc-switch` copies the Windows `.claude.json` into the WSL home.
- After a successful switch, restart Claude Code or open a fresh session so the live config is reloaded.

## Pinned Provider Overrides

- If `cc-switch provider switch` reports success but Claude or a `cc-connect` bot still behaves like the old provider, inspect both `~/.claude/settings.json` and `/mnt/c/Users/<WindowsUser>/.claude/settings.json`.
- Global `env` keys such as `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_REASONING_MODEL`, and the `ANTHROPIC_DEFAULT_*` model keys can pin Claude to one provider regardless of the `cc-switch` database.
- Back up those `settings.json` files before editing.
- Remove only the `ANTHROPIC_*` override keys when the goal is to let `cc-switch` drive provider selection; keep unrelated telemetry, timeout, or permission keys intact.
- For Telegram/`cc-connect` flows, restart `cc-connect` after clearing those overrides so the next Claude child process loads the updated settings.

## Telegram Session Freshness

- For `cc-connect` + Telegram bots, a successful provider/config fix is not enough if the bot keeps resuming an old Claude session.
- After changing Claude provider settings and restarting `cc-connect`, send `/new` again before testing with a normal message.
- Read the `cc-connect` log when behavior still looks stale:
  - `session spawned ... is_resume=true` means the bot resumed an old Claude session.
  - `cmdNew: cleanup done, creating new session` followed by `session spawned ... is_resume=false` means the bot really got a fresh Claude session.
- If the post-fix test still hits `is_resume=true`, the failure is session reuse rather than provider switching.

## Resources

### scripts/

- `cc-switch-run.sh`: Run `cc-switch` against the WSL or Windows-backed home, plus a `doctor` mode for cross-home diagnosis.
