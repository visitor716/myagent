---
name: cc-connect-bot-setup
description: Configure and diagnose cc-connect Telegram bot bridges, especially per-bot Claude Code and Codex permission modes, full-auto defaults, WSL/systemd startup fallback, config backups, and safe restarts. Use when the user mentions cc-connect, Telegram bot bridge permissions, full-auto/suggest/plan/yolo modes, or restarting cc-connect.
---

# cc-connect Bot Setup

Use this skill to manage `cc-connect` as the bridge from local coding agents to Telegram or other IM platforms.

Canonical user config:

- Config: `~/.cc-connect/config.toml`
- Logs: `~/.cc-connect/logs/cc-connect.log`
- Daemon metadata: `~/.cc-connect/daemon.json`
- Project source of truth: `/home/zhanxp/projects/myagent/skills/cc-connect-bot-setup`

## Safety Rules

- Treat Telegram tokens and API keys as secrets. Mask them in all user-facing output.
- Back up `~/.cc-connect/config.toml` before modifying it.
- Do not restart `cc-connect` unless the user asked for restart. Config edits alone are enough when the user wants to restart later.
- Prefer `full-auto` for Codex automation because it keeps the workspace sandbox. Use `yolo` only when the user explicitly asks for no approvals and no sandbox.
- Keep `allow_from` or `admin_from` restricted to trusted user IDs for full-auto bots. Do not loosen access while changing permission mode.

## Permission Modes

Configure modes per `[[projects]]` block. One project owns one agent config and one or more platform entries. If two Telegram bots need different permissions, put them in different `[[projects]]` blocks.

Claude Code agent:

```toml
[projects.agent]
type = "claudecode"

[projects.agent.options]
mode = "bypassPermissions"
```

Claude Code modes:

- `default`: every tool call requires approval
- `acceptEdits`: edit tools auto-approved, other tools still ask
- `plan`: read-only planning mode
- `bypassPermissions`: all tool calls auto-approved

Codex agent:

```toml
[projects.agent]
type = "codex"

[projects.agent.options]
mode = "full-auto"
```

Codex modes:

- `suggest`: ask permission for every tool call
- `auto-edit`: auto-approve file edits, ask for shell commands
- `full-auto`: auto-approve everything with workspace sandbox
- `yolo`: bypass approvals and sandbox

## Full-Auto Update Workflow

When the user asks to make all `cc-connect` bots full-auto:

1. Read `~/.cc-connect/config.toml` and identify every `[[projects]]` block.
2. Update only `[projects.agent.options].mode`:
   - `claudecode` -> `bypassPermissions`
   - `codex` -> `full-auto`
3. Preserve tokens, `allow_from`, `admin_from`, `work_dir`, comments, and unrelated settings.
4. Report the project names, agent types, and resulting modes with secrets masked.
5. Tell the user to restart `cc-connect` and send `/new` in each Telegram bot if they want fresh sessions under the new default mode.

Prefer the bundled script for repeatability:

```bash
python3 /home/zhanxp/projects/myagent/skills/cc-connect-bot-setup/scripts/set_cc_connect_modes.py \
  --config ~/.cc-connect/config.toml
```

Use `--dry-run` to preview the project summary without writing.

## Restart Guidance

If systemd user services are available:

```bash
cc-connect daemon restart
cc-connect daemon logs -n 50
```

In WSL without systemd, `cc-connect daemon status` may report that the systemd user session is unavailable. Do not keep retrying systemd. Start with the same binary recorded in `~/.cc-connect/daemon.json` or the installed npm path:

```bash
cd ~/.cc-connect
env CC_LOG_FILE=~/.cc-connect/logs/cc-connect.log \
    CC_LOG_MAX_SIZE=10485760 \
    setsid -f ~/.nvm/versions/node/v20.20.2/lib/node_modules/cc-connect/bin/cc-connect \
    >~/.cc-connect/logs/cc-connect.nohup.log 2>&1
```

Verify:

```bash
pgrep -af 'cc-connect|codex|claude'
tail -n 80 ~/.cc-connect/logs/cc-connect.log
```

Expected evidence after restart:

- `cc-connect is running`
- `engine started` for each configured project
- Claude Code sessions launch with `--permission-mode bypassPermissions`
- Codex sessions no longer generate approval requests for normal full-auto work

## Recovery

If a permission change is wrong, restore the newest backup named like:

```text
~/.cc-connect/config.toml.bak.fullauto.YYYYmmdd-HHMMSS
```

Then restart `cc-connect`.
