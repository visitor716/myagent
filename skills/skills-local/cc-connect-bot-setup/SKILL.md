---
name: cc-connect-bot-setup
description: Configure and diagnose cc-connect Telegram bot bridges and Claude Code permission defaults, especially per-bot Claude Code/Codex modes, global Claude Code startup bypassPermissions, full-auto defaults, WSL/systemd startup fallback, config backups, and safe restarts. Use when the user mentions cc-connect, Telegram bot bridge permissions, Claude/Cloud Code permission boundaries, bypassPermissions, full-auto/suggest/plan/yolo modes, or restarting cc-connect.
---

# cc-connect Bot Setup

Use this skill to manage `cc-connect` as the bridge from local coding agents to Telegram or other IM platforms.

Canonical user config:

- Config: `~/.cc-connect/config.toml`
- Logs: `~/.cc-connect/logs/cc-connect.log`
- Daemon metadata: `~/.cc-connect/daemon.json`
- Skill source of truth: `/home/zhanxp/projects/myagent/skills/skills-local/cc-connect-bot-setup`
- Claude Code user settings: `~/.claude/settings.json`
- Claude Code template: `/home/zhanxp/projects/myagent/configs/claude-code/settings.json`

## Safety Rules

- Treat Telegram tokens and API keys as secrets. Mask them in all user-facing output.
- Do not print full Claude settings when they contain `env` tokens; show only relevant permission keys.
- Back up `~/.cc-connect/config.toml` before modifying it.
- Back up `~/.claude/settings.json` before modifying Claude Code defaults.
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
python3 /home/zhanxp/projects/myagent/skills/skills-local/cc-connect-bot-setup/scripts/set_cc_connect_modes.py \
  --config ~/.cc-connect/config.toml
```

Use `--dry-run` to preview the project summary without writing.

## Claude Code Global Default Bypass

When the user asks to make Claude/Cloud Code start in Bypass Permissions by default:

1. Back up `~/.claude/settings.json` to `~/.claude/settings.json.bak.bypass-YYYYmmdd-HHMMSS`.
2. In `~/.claude/settings.json`, preserve existing keys and set:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true
}
```

3. Apply the same two settings to `/home/zhanxp/projects/myagent/configs/claude-code/settings.json` so config restore/sync does not regress the default.
4. Validate both files with a JSON parser, for example:

```bash
node -e "for (const f of [process.env.HOME + '/.claude/settings.json', '/home/zhanxp/projects/myagent/configs/claude-code/settings.json']) JSON.parse(require('fs').readFileSync(f, 'utf8'))"
```

5. Report that only new Claude Code sessions pick up the default. Existing sessions must be restarted or recreated.
6. Mention the remaining Claude Code exceptions: protected paths such as `.git`, most `.claude`, `.mcp.json`, `.claude.json`, and shell rc files may still prompt; web/remote-control entrypoints may not support bypass mode.

## Latency Tuning

When the user reports slow Telegram replies:

1. Read recent logs first:
   - `tail -n 260 ~/.cc-connect/logs/cc-connect.log`
   - `tail -n 120 ~/.cc-connect/logs/cc-connect.nohup.log ~/.cc-connect/logs/cc-connect.err.log`
2. Distinguish the bottleneck:
   - `processing message` appears quickly, but `slow agent first event` appears later: model/agent startup or context/tool work is slow.
   - `permission request` waits for minutes: the running session is still in a manual/plan mode; restart `cc-connect` after config changes and send `/new`.
   - `getUpdates unexpected EOF` or `i/o timeout`: Telegram long polling/network path is unstable; expect 3s retry gaps and consider a stable proxy/network.
3. Enable streaming preview for better mobile perceived latency:

```toml
[stream_preview]
enabled = true
interval_ms = 1200
min_delta_chars = 25
max_chars = 1800
```

4. Verify active child processes. If `claude --permission-mode plan` is still running after config says `bypassPermissions`, the service has not restarted and old sessions are still active.
5. After restart, send `/new` in each Telegram bot to create fresh sessions under the new mode.

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

## Disable / Handoff to TG Organ Manager

When the user says CC Connect is no longer the Telegram bot owner because TG Organ Manager now manages bot configuration and organs:

1. Do not delete `~/.cc-connect/config.toml` or tokens unless the user explicitly asks for credential cleanup.
2. Back up crontab, then comment CC Connect watchdog entries only:

```bash
mkdir -p ~/.cc-connect/crons
crontab -l > ~/.cc-connect/crons/crontab.bak.disable-cc-connect-$(date +%Y%m%d-%H%M%S)
crontab -l | awk '{ if ($0 ~ /^@reboot .*cc-connect-watchdog\.sh start-supervisor/) print "# disabled " strftime("%Y-%m-%d") ": " $0; else print $0 }' | crontab -
```

3. Stop active CC Connect/watchdog process groups:

```bash
pgid="$(pgrep -af 'cc-connect-watchdog.sh loop' | awk 'NR==1 { print $1 }' | xargs -r ps -o pgid= -p | tr -d ' ')"
if [ -n "$pgid" ]; then kill -TERM -"$pgid"; fi
```

4. Verify stopped:

```bash
~/.cc-connect/bin/cc-connect-watchdog.sh status
pgrep -af 'cc-connect|cc-connect-watchdog' || true
crontab -l
```

Expected evidence:

- `supervisor=stopped`
- `cc_connect=stopped`
- CC Connect `@reboot` line is commented
- No persistent `cc-connect` or `cc-connect-watchdog.sh loop` process remains

## Windows Terminal Jumping / TTY Attachment

When the user reports Windows Terminal jumping, scrolling, or tabs being affected by CC Connect:

1. Check daemon state and process ownership:

```bash
cc-connect daemon status
pgrep -af 'cc-connect|cc-connect-watchdog'
ps -p <watchdog-pid>,<cc-connect-pid> -o pid,ppid,pgid,sid,tty,stat,lstart,cmd
pstree -aps <pid>
```

2. Check whether file descriptors still point at an interactive terminal:

```bash
ls -l /proc/<watchdog-pid>/fd /proc/<cc-connect-pid>/fd
```

Risk signal:

- `TTY` is `pts/N`, or fd `0`, `1`, `2` points to `/dev/pts/N`

Expected detached state:

- `TTY` is `?`
- stdin is `/dev/null`
- stdout/stderr point to `~/.cc-connect/logs/*.log`

3. If the watchdog was launched from an interactive terminal, change its `start_supervisor` line from `nohup "$0" loop ... &` to:

```bash
setsid -f "$0" loop >> "$WATCHDOG_LOG" 2>&1 < /dev/null &
```

4. Restart the watchdog and re-check `ps` plus `/proc/<pid>/fd`.

## Hermes ACP Empty Reply / HTTP 400

When a Telegram bot has been switched to `agent.type = "acp"` with Hermes, but the bot returns an empty reply or the session dies immediately, check for a Hermes model/provider mismatch before blaming `cc-connect`.

Typical symptom in `~/.cc-connect/logs/cc-connect.log`:

- `agent=acp` session starts with `is_resume=false`
- Hermes stderr shows `Auxiliary auto-detect: using main provider openai-codex (anthropic/claude-opus-4.6)`
- Then an HTTP 400 from `https://chatgpt.com/backend-api/codex`
- Error text says the Claude model is not supported for a ChatGPT/Codex account

Root cause:

- `~/.hermes/config.yaml` still points `model.default` at an OpenRouter-style Claude model such as `anthropic/claude-opus-4.6`
- But Hermes only has `OpenAI Codex` logged in and no `OPENROUTER_API_KEY`
- Provider auto-detect falls back to `openai-codex`, then sends an incompatible model slug and fails

Diagnosis:

```bash
hermes status
tail -n 120 ~/.cc-connect/logs/cc-connect.log
hermes chat -Q --provider openai-codex -q 'Reply with exactly OK.'
```

If `hermes status` shows:

- `Model: anthropic/claude-opus-4.6`
- `Provider: OpenAI Codex`
- `OpenRouter ✗ (not set)`
- `OpenAI Codex ✓ logged in`

then the config is inconsistent.

Minimal fix for a Codex-backed Hermes setup:

```bash
cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak.hermes-codex-fix-$(date +%Y%m%d-%H%M%S)
hermes config set model.provider openai-codex
hermes config set model.default gpt-5.5
hermes config set model.base_url https://chatgpt.com/backend-api/codex
```

Then verify again:

```bash
hermes status
hermes chat -Q --provider openai-codex -q 'Reply with exactly OK.'
cc-connect daemon restart
```

After the restart, send `/new` to the Telegram bot before testing so the project does not resume an old broken ACP session.

## Recovery

If a permission change is wrong, restore the newest backup named like:

```text
~/.cc-connect/config.toml.bak.fullauto.YYYYmmdd-HHMMSS
```

Then restart `cc-connect`.
