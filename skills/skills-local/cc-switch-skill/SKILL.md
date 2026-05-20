---
name: cc-switch-skill
description: Diagnose and operate cc-switch from WSL or Windows-backed homes. Use when the user mentions cc-switch, providers, models, APIs, provider-count mismatches, Windows GUI database initialization failures such as “database is locked”, wants to list/switch/add/edit/validate cc-switch providers, or says phrases such as “切换到百度 CC” / “百度 CC” to switch bdcc1 Claude Code to Baidu Qianfan.
---

# CC Switch Skill

Use this skill to manage `cc-switch`, especially from WSL where Linux and Windows may have separate `~/.cc-switch` databases.

Canonical paths:

- WSL database: `~/.cc-switch/cc-switch.db`
- Windows database from WSL: `/mnt/c/Users/<WindowsUser>/.cc-switch/cc-switch.db`
- Windows app Store override from WSL: `/mnt/c/Users/<WindowsUser>/AppData/Roaming/com.ccswitch.desktop/app_paths.json`
- Windows app log from WSL: `/mnt/c/Users/<WindowsUser>/.cc-switch/logs/cc-switch.log`
- Isolated worker database: `<worker-home>/.cc-switch/cc-switch.db`
- Isolated Claude live settings: `<worker-home>/.claude/settings.json`
- Skill source of truth: `/home/zhanxp/projects/myagent/skills/skills-local/cc-switch-skill`

## Safety Rules

- Treat provider secrets as sensitive. Prefer `provider list`, `provider current`, and `config validate`; do not print full config blobs unless the user explicitly asks.
- Distinguish **providers/APIs** from **models**. `provider list` and `config validate` count providers, not the model names attached to a provider.
- If the user says “cc-switch 软件”, “Windows app”, “GUI”, or reports counts seen in the Windows app, assume the Windows database is the likely source of truth until proven otherwise.
- Before editing providers on an existing database, create a backup with `config backup` or copy the target `cc-switch.db`.
- Before editing the Windows app Store override, back up `app_paths.json` and both likely databases when they exist.
- If the Windows GUI reports `Database Initialization Failed` / `database is locked` and the displayed path starts with `\\wsl.localhost\...`, treat cross-OS SQLite locking as the likely cause. Prefer redirecting the GUI to `C:\Users\<WindowsUser>\.cc-switch`; manage the WSL database from WSL CLI instead of forcing the GUI to open it over UNC.
- Do not enter real provider secrets into interactive `cc-switch provider add` unless there is no alternative. In a TTY, prompts can echo typed input into logs/transcripts. Prefer `scripts/configure-claude-provider.py` with `--api-key-env`, `--api-key-file`, or `--api-key-stdin`.
- For Telegram worker homes such as `BDCC1_HOME` and `BDCC2_HOME`, configure the worker's isolated HOME, not the leader user's default `~/.cc-switch`.

## Default Workflow

1. Run `bash scripts/cc-switch-run.sh doctor` first.
2. If the Windows app is the source of truth, use `--windows`.
3. If the user explicitly wants the WSL-local CLI database, use `--wsl`.
4. If the target is an isolated bot/worker, resolve its `HOME` from the project config or environment and use `--home <path>`.
5. If the target is unclear, use `--auto`; it prefers the home with the larger provider count.
6. After modifications, rerun `config validate` and `provider current` against the same target home.

## Windows GUI Database Locked

Use this path when the Windows desktop app shows `Database Initialization Failed` or `database is locked`.

Diagnosis:

```bash
bash scripts/cc-switch-run.sh doctor
tail -n 80 /mnt/c/Users/<WindowsUser>/.cc-switch/logs/cc-switch.log
tail -n 80 ~/.cc-switch/logs/cc-switch.log
sed -n '1,80p' /mnt/c/Users/<WindowsUser>/AppData/Roaming/com.ccswitch.desktop/app_paths.json
sqlite3 ~/.cc-switch/cc-switch.db 'PRAGMA quick_check; PRAGMA integrity_check;'
sqlite3 /mnt/c/Users/<WindowsUser>/.cc-switch/cc-switch.db 'PRAGMA quick_check; PRAGMA integrity_check;'
powershell.exe -NoProfile -Command 'Get-Process -Name cc-switch -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path | Format-Table -AutoSize'
```

Interpretation:

- If the error dialog or `app_paths.json` points to `\\wsl.localhost\Ubuntu\home\<user>\.cc-switch`, the GUI is opening the WSL SQLite database over a Windows UNC path. This can fail with SQLite lock errors even when WSL CLI validation succeeds.
- If both `quick_check` and `config validate` pass, do not treat the database as corrupted. Fix the app config path before considering restore or migration.

Fix:

```bash
WIN_USER=<WindowsUser>
TS=$(date +%Y%m%d-%H%M%S)
WIN_HOME="/mnt/c/Users/$WIN_USER"
STORE="$WIN_HOME/AppData/Roaming/com.ccswitch.desktop/app_paths.json"

powershell.exe -NoProfile -Command 'Stop-Process -Name cc-switch -Force -ErrorAction SilentlyContinue'
mkdir -p "$WIN_HOME/.cc-switch/backups" "$HOME/.cc-switch/backups"
cp "$STORE" "$WIN_HOME/.cc-switch/backups/app_paths.json.before-wsl-unc-db-fix-$TS"
cp "$WIN_HOME/.cc-switch/cc-switch.db" "$WIN_HOME/.cc-switch/backups/cc-switch.windows.before-wsl-unc-db-fix-$TS.db"
cp "$HOME/.cc-switch/cc-switch.db" "$HOME/.cc-switch/backups/cc-switch.wsl.before-wsl-unc-db-fix-$TS.db"
```

Then update `app_paths.json` to:

```json
{
  "app_config_dir_override": "C:\\Users\\<WindowsUser>\\.cc-switch"
}
```

Verify:

```bash
python3 -m json.tool "$STORE" >/dev/null
bash scripts/cc-switch-run.sh --windows config validate
bash scripts/cc-switch-run.sh --wsl config validate
powershell.exe -NoProfile -Command 'Start-Process -FilePath "<cc-switch.exe path from Get-Process>"; Start-Sleep -Seconds 4; Get-Process -Name cc-switch -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,MainWindowTitle,Path | Format-List'
tail -n 80 "$WIN_HOME/.cc-switch/logs/cc-switch.log"
```

Success criteria:

- Windows log says it is using `C:\Users\<WindowsUser>\.cc-switch`.
- Windows log reaches `正常启动模式：主窗口已显示`.
- No new `Failed to init database` entry appears after restart.

If Windows and WSL provider counts differ after this fix, explain that the GUI now reads the Windows database while WSL CLI reads the WSL database. Sync or import providers only after backing up both sides.

## Fixed Intent: "切换到百度 CC"

When the user says exactly or approximately “切换到百度 CC”, “切百度 CC”, “百度 CC”, or “切到百度千帆 CC”, execute the `tg-agent-gateway` `bdcc1` provider switch without asking for confirmation.

Interpretation:

- Target worker: `bdcc1`
- Target app: Claude Code / `claude`
- Target provider ID: `baidu-qianfan`
- Target model: `qianfan-code-latest`
- Target HOME: read `BDCC1_HOME` from `/home/zhanxp/projects/tg-agent-gateway/.env`; fallback to `/home/zhanxp/.agents/bdcc1`
- Do not switch the leader user's default `~/.cc-switch`
- Do not print secrets or full config blobs
- Do not start or restart the proxy unless the user also asks for proxy/startup

Execution:

```bash
cd /home/zhanxp/projects/tg-agent-gateway
set -a
[ -f .env ] && . ./.env
set +a
BDCC1_HOME="${BDCC1_HOME:-/home/zhanxp/.agents/bdcc1}"
HOME="$BDCC1_HOME" cc-switch provider switch -a claude baidu-qianfan
HOME="$BDCC1_HOME" cc-switch provider current -a claude
HOME="$BDCC1_HOME" cc-switch provider stream-check -a claude baidu-qianfan
```

Success criteria:

- The switch command reports `Switched to provider 'baidu-qianfan'`.
- `provider current -a claude` shows `baidu-qianfan` / `Baidu Qianfan` as current.
- API URL is `https://qianfan.baidubce.com/anthropic/coding`.
- Model configuration shows `qianfan-code-latest` for Main, Haiku, Sonnet, and Opus; do not leave these fields as `default`, because Qianfan rejects Coding Plan requests for the default model.
- `provider stream-check -a claude baidu-qianfan` returns HTTP 200 with model `qianfan-code-latest`.

If the user is testing through Telegram, remind them that existing Claude Code sessions keep the old loaded config. New `bdcc1` tasks use the new provider; already-running Claude CLI sessions must be restarted.

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

# Inspect an isolated worker home
bash scripts/cc-switch-run.sh --home /home/zhanxp/.agents/bdcc1 --app claude provider current

# Switch bdcc1's underlying Claude Code provider to Baidu Qianfan
HOME=/home/zhanxp/.agents/bdcc1 cc-switch provider switch -a claude baidu-qianfan
HOME=/home/zhanxp/.agents/bdcc1 cc-switch provider list -a claude

# Start the local cc-switch proxy in tmux; proxy serve is foreground by design
cc-switch proxy show
tmux new-session -d -s cc-switch-proxy \
  'cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log'
cc-switch proxy show

# Non-interactively upsert an Anthropic-compatible Claude provider for worker homes.
# Keep the secret outside the command line when possible.
export PROVIDER_API_KEY='...'
python3 scripts/configure-claude-provider.py \
  --home /home/zhanxp/.agents/bdcc1 \
  --home /home/zhanxp/.agents/bdcc2 \
  --id baidu-qianfan \
  --name 'Baidu Qianfan' \
  --base-url 'https://qianfan.baidubce.com/anthropic/coding' \
  --model 'qianfan-code-latest' \
  --api-key-env PROVIDER_API_KEY \
  --category cn_official \
  --website-url 'https://cloud.baidu.com/product/wenxinworkshop'
```

## Isolated Worker Homes

Some Telegram or `cc-connect` workers run Claude Code with a custom `HOME`, for example:

- `BDCC1_HOME=/home/zhanxp/.agents/bdcc1`
- `BDCC2_HOME=/home/zhanxp/.agents/bdcc2`

For these workers, `cc-switch` state and Claude live config are both under the worker HOME. Configure and verify that HOME directly:

```bash
bash scripts/cc-switch-run.sh --home "$BDCC1_HOME" config validate
bash scripts/cc-switch-run.sh --home "$BDCC1_HOME" --app claude provider current
```

For `tg-agent-gateway`, resolve worker homes from `.env` and `data/bots.json`. `bdcc1` currently uses `BDCC1_HOME=/home/zhanxp/.agents/bdcc1`; do not switch the leader user's default provider when the user asks for `bdcc1`:

```bash
HOME="$BDCC1_HOME" cc-switch provider list -a claude
HOME="$BDCC1_HOME" cc-switch provider switch -a claude baidu-qianfan
HOME="$BDCC1_HOME" cc-switch provider list -a claude
```

Expected verification for the Baidu Qianfan lane:

- `provider switch` prints `Switched to provider 'baidu-qianfan'`.
- `provider list -a claude` shows `baidu-qianfan` / `Baidu Qianfan` with the current-provider marker.
- API URL is `https://qianfan.baidubce.com/anthropic/coding`.
- Model configuration shows `qianfan-code-latest`, not `default`.
- `HOME="$BDCC1_HOME" cc-switch provider stream-check -a claude baidu-qianfan` succeeds with HTTP 200.

Existing Claude Code processes keep their old loaded config. New Telegram Gateway tasks spawned for `bdcc1` use the worker HOME and pick up the new provider; already-running Claude CLI sessions must be restarted.

When adding an Anthropic-compatible provider, prefer the helper:

```bash
python3 scripts/configure-claude-provider.py \
  --home "$BDCC1_HOME" \
  --id <provider-id> \
  --name '<provider-name>' \
  --base-url '<anthropic-compatible-base-url>' \
  --model '<model-name>' \
  --api-key-env PROVIDER_API_KEY
```

The helper:

- Initializes the target cc-switch database when needed.
- Backs up `cc-switch.db`, `.claude/settings.json`, and `.claude.json` when present.
- Syncs `common_config_claude` from the current user's cc-switch database by default.
- Marks the provider current unless `--no-current` is used.
- Exports `<worker-home>/.claude/settings.json` and sets mode `600`.
- Runs `cc-switch config validate` and `provider current` before reporting success.

If the worker runner sets `HOME` and clears `CLAUDE_CONFIG_DIR`, Claude Code will read the worker-local `.claude/settings.json`. If the bot still uses an old provider, restart the process that spawns Claude and start a fresh session.

## Local Proxy Operation

`cc-switch proxy serve` runs in the foreground. For long-running local use, start it under tmux and verify both `cc-switch proxy show` and the listening port:

```bash
cc-switch proxy show
tmux has-session -t cc-switch-proxy || \
  tmux new-session -d -s cc-switch-proxy \
    'cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log'
cc-switch proxy show
ss -ltnp | rg ':15721'
tail -n 60 logs/runtime/cc-switch-proxy.log
```

If the proxy must use an isolated worker database, start it with that worker's HOME instead and remember the port is shared:

```bash
HOME="$BDCC1_HOME" cc-switch proxy show
HOME="$BDCC1_HOME" cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721
```

Do not run multiple proxy instances on `127.0.0.1:15721`; stop or reuse the existing `cc-switch-proxy` tmux session first.

## Hot Switch Semantics

Provider "hot deploy" is possible only for clients that were already started through the local proxy. It is not possible to reliably mutate `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, or already-loaded Claude settings inside an existing direct-to-provider Claude process.

Use this rule:

- Existing Claude process with `ANTHROPIC_BASE_URL=http://127.0.0.1:15721`: switching the current provider can affect the next request without restarting Claude.
- Existing Claude process with empty `ANTHROPIC_BASE_URL` or a direct provider URL such as `https://ark...`: not hot-switchable; restart Claude once under proxy.
- Telegram Gateway worker tasks usually spawn fresh Claude child processes, so provider switches apply to the next task if the worker HOME/settings are correct.

Check current Claude processes without printing secrets:

```bash
python3 - <<'PY'
import os, re
for pid in sorted(p for p in os.listdir('/proc') if p.isdigit()):
    try:
        cmd = open(f'/proc/{pid}/cmdline','rb').read().replace(b'\0', b' ').decode('utf-8','ignore').strip()
        if not re.search(r'(^|/)claude(\s|$)', cmd):
            continue
        env = {}
        for item in open(f'/proc/{pid}/environ','rb').read().split(b'\0'):
            if b'=' in item:
                k, v = item.split(b'=', 1)
                key = k.decode('utf-8','ignore')
                if key in {'HOME','ANTHROPIC_BASE_URL','CLAUDE_CONFIG_DIR'}:
                    env[key] = v.decode('utf-8','ignore')
        print(f"pid={pid} HOME={env.get('HOME','')} ANTHROPIC_BASE_URL={env.get('ANTHROPIC_BASE_URL','')}")
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
PY
```

For future hot-switchable Claude sessions, configure Claude to use the proxy URL, keep real upstream credentials only in cc-switch providers, start the proxy, then switch providers:

```bash
cc-switch proxy show
tmux has-session -t cc-switch-proxy || \
  tmux new-session -d -s cc-switch-proxy \
    'cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log'

# Once Claude is using http://127.0.0.1:15721, this changes the next proxied request.
cc-switch provider switch -a claude baidu-qianfan
cc-switch proxy show
```

If an existing terminal was opened before proxy routing was configured, explain that one restart is required to enter proxy mode; after that, future provider switches can be hot.

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
- `configure-claude-provider.py`: Non-interactively upsert, activate, export, back up, and verify a Claude provider for one or more HOME directories.
