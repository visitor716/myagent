---
name: my-cc-switch-skill
description: Diagnose and operate cc-switch from WSL or Windows-backed homes. Use when the user mentions cc-switch, providers, models, APIs, provider-count mismatches, Windows GUI database initialization failures such as “database is locked” or “database disk image is malformed”, Volcengine/火山方舟/豆包/Kimi provider failures, CLI/GUI schema mismatches, wants to list/switch/add/edit/validate cc-switch providers, or says phrases such as “切换到百度 CC” / “百度 CC” to switch bdcc1 Claude Code to Baidu Qianfan.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-cc-switch-skill` once near the start; if it fails, continue.


# CC Switch Skill

Use this skill to manage `cc-switch`. The default contract is that the Windows GUI and this skill operate the same `cc-switch` configuration store: the GUI is the human interface, and this skill is the agent interface. In WSL, prefer the Windows GUI's configured home as the shared operation target unless the user explicitly asks for WSL-local or isolated worker state.

Canonical paths:

- Shared GUI database from WSL: `/mnt/c/Users/<WindowsUser>/.cc-switch/cc-switch.db` by default, or the home derived from the Windows app Store override.
- WSL-local database: `~/.cc-switch/cc-switch.db` (explicit `--wsl` only; not the normal shared GUI object)
- Windows app Store override from WSL: `/mnt/c/Users/<WindowsUser>/AppData/Roaming/com.ccswitch.desktop/app_paths.json`
- Windows app log from WSL: `/mnt/c/Users/<WindowsUser>/.cc-switch/logs/cc-switch.log`
- Isolated worker database: `<worker-home>/.cc-switch/cc-switch.db`
- Isolated Claude live settings: `<worker-home>/.claude/settings.json`
- Skill source of truth: `/home/zhanxp/projects/myagent/skills/skills-local/cc-switch-skill`

## Safety Rules

- Treat provider secrets as sensitive. Prefer `provider list`, `provider current`, and `config validate`; do not print full config blobs unless the user explicitly asks.
- Distinguish **providers/APIs** from **models**. `provider list` and `config validate` count providers, not the model names attached to a provider.
- For normal provider/model/list/switch actions, use the same cc-switch home as the Windows GUI. Do not choose the WSL-local database just because it has more providers.
- If the user says “cc-switch 软件”, “Windows app”, “GUI”, or reports counts seen in the Windows app, treat the GUI store as the source of truth and operate that same store from the skill.
- Before editing providers on an existing database, create a backup with `config backup` or copy the target `cc-switch.db`.
- Before editing the Windows app Store override, back up `app_paths.json` and both likely databases when they exist.
- If the Windows GUI reports `Database Initialization Failed` / `database is locked` and the displayed path starts with `\\wsl.localhost\...`, treat cross-OS SQLite locking as the likely cause. Prefer redirecting the GUI to `C:\Users\<WindowsUser>\.cc-switch`; manage the WSL database from WSL CLI instead of forcing the GUI to open it over UNC.
- Do not enter real provider secrets into interactive `cc-switch provider add` unless there is no alternative. In a TTY, prompts can echo typed input into logs/transcripts. Prefer `scripts/configure-claude-provider.py` with `--api-key-env`, `--api-key-file`, or `--api-key-stdin`.
- For Telegram worker homes such as `BDCC1_HOME` and `BDCC2_HOME`, configure the worker's isolated HOME, not the leader user's default `~/.cc-switch`.

## Default Workflow

1. Run `bash scripts/cc-switch-run.sh doctor` first.
2. For normal user-facing `cc-switch` actions, use the default mode or `--gui`; this targets the same home that the Windows GUI uses.
3. If the user explicitly wants the WSL-local CLI database, use `--wsl`.
4. If the target is an isolated bot/worker, resolve its `HOME` from the project config or environment and use `--home <path>`.
5. If the target is unclear, use `--auto`; it prefers the Windows GUI home when available.
6. After modifications, rerun `config validate`, `provider current`, and provider-specific `stream-check` against the same target home.
7. Run cc-switch commands that may write health logs or migrate databases serially; parallel `provider current`, `config validate`, and `stream-check` can create transient SQLite locks.

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

If Windows and WSL provider counts differ after this fix, treat the Windows GUI database as the normal shared object. Use the WSL database only for explicit WSL-local work, or sync/import providers only after backing up both sides.

## Windows GUI Database Malformed or Too New

Use this path when the shared GUI store fails with `database disk image is malformed`, `cannot start a transaction within a transaction`, or `数据库版本过新`.

Diagnosis:

```bash
cc-switch --version
HOME=/mnt/c/Users/<WindowsUser> cc-switch config validate
sqlite3 /mnt/c/Users/<WindowsUser>/.cc-switch/cc-switch.db 'PRAGMA quick_check; PRAGMA integrity_check;'
powershell.exe -NoProfile -Command 'Get-Process -Name cc-switch -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path | Format-Table -AutoSize'
```

Rules:

- If the database says schema/user_version is too new, run `cc-switch update` before editing data.
- If `PRAGMA integrity_check` reports `database disk image is malformed`, stop the Windows GUI, back up the malformed DB, and rebuild from `.dump`; do not keep writing to the malformed DB.
- If all `.db` backups also fail `PRAGMA quick_check`, prefer `.dump` from the current DB before falling back to older SQL exports.
- Expect `/mnt/c` permissions to show as `0777` in WSL; treat that as a warning, not a validation failure, when `config validate` and `stream-check` pass.

Recovery:

```bash
WIN_USER=<WindowsUser>
WIN_HOME="/mnt/c/Users/$WIN_USER"
TS=$(date +%Y%m%d-%H%M%S)

powershell.exe -NoProfile -Command 'Stop-Process -Name cc-switch -Force -ErrorAction SilentlyContinue'
cp "$WIN_HOME/.cc-switch/cc-switch.db" "$WIN_HOME/.cc-switch/backups/cc-switch.gui.malformed.before-rebuild-$TS.db"

DUMP_SQL="/tmp/ccswitch-gui-dump-$TS.sql"
DUMP_DB="/tmp/ccswitch-gui-dumped-$TS.db"
sqlite3 "$WIN_HOME/.cc-switch/cc-switch.db" .dump > "$DUMP_SQL"
sqlite3 "$DUMP_DB" < "$DUMP_SQL"
sqlite3 "$DUMP_DB" 'PRAGMA quick_check; PRAGMA integrity_check;'
cp "$DUMP_DB" "$WIN_HOME/.cc-switch/cc-switch.db"
```

Then rerun:

```bash
HOME="$WIN_HOME" cc-switch config validate
HOME="$WIN_HOME" cc-switch provider current -a claude
```

Restart the GUI only after validation:

```bash
powershell.exe -NoProfile -Command 'Start-Process -FilePath "<cc-switch.exe path>"; Start-Sleep -Seconds 4; Get-Process -Name cc-switch -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path | Format-Table -AutoSize'
```

## Volcengine Ark / 火山方舟 Unavailable

Use this path when the user says 火山方舟, Volcengine Ark, 豆包, Kimi, or `ark.cn-beijing.volces.com` is unavailable.

Diagnosis:

```bash
GUI_HOME="$(bash scripts/cc-switch-run.sh --gui print-home)"
HOME="$GUI_HOME" cc-switch provider current -a claude
HOME="$GUI_HOME" cc-switch provider fetch-models -a claude <provider-id>
HOME="$GUI_HOME" cc-switch provider stream-check -a claude <provider-id>
```

Interpretation:

- If `stream-check` succeeds but `provider current` shows Main/Haiku/Sonnet/Opus as `default`, treat the provider as misconfigured for Claude Code even though the endpoint and key are valid.
- `https://ark.cn-beijing.volces.com/api/coding` may host multiple provider records, for example `火山方舟` and `Kimi`; compare their model fields before editing.
- Do not use `provider export` as a read-only inspection command inside a repo; it writes `.claude/settings.local.json` in the current directory and can contain provider config. Delete that file if accidentally created.

Fix the selected 火山方舟 provider by backing up the target DB and setting an explicit code-capable model:

```bash
TARGET_HOME="$(bash scripts/cc-switch-run.sh --gui print-home)"
PROVIDER_ID="2d1171e6-412d-4013-919f-6b9a13beaf41"
MODEL="doubao-seed-2-0-code-preview-260215"
TS=$(date +%Y%m%d-%H%M%S)

mkdir -p "$TARGET_HOME/.cc-switch/backups"
cp "$TARGET_HOME/.cc-switch/cc-switch.db" "$TARGET_HOME/.cc-switch/backups/cc-switch.before-volc-ark-model-fix-$TS.db"

sqlite3 "$TARGET_HOME/.cc-switch/cc-switch.db" <<SQL
UPDATE providers
SET settings_config = json_set(
  settings_config,
  '$.model', '$MODEL',
  '$.env.ANTHROPIC_MODEL', '$MODEL',
  '$.env.ANTHROPIC_DEFAULT_HAIKU_MODEL', '$MODEL',
  '$.env.ANTHROPIC_DEFAULT_SONNET_MODEL', '$MODEL',
  '$.env.ANTHROPIC_DEFAULT_OPUS_MODEL', '$MODEL',
  '$.env.ANTHROPIC_REASONING_MODEL', '$MODEL'
)
WHERE app_type='claude' AND id='$PROVIDER_ID';
SELECT changes();
SQL
```

Verify:

```bash
HOME="$TARGET_HOME" cc-switch config validate
HOME="$TARGET_HOME" cc-switch provider current -a claude
HOME="$TARGET_HOME" cc-switch provider stream-check -a claude "$PROVIDER_ID"
```

Success criteria:

- `provider current` shows Main, Haiku, Sonnet, and Opus as `doubao-seed-2-0-code-preview-260215`, not `default`.
- `stream-check` returns HTTP 200 and reports model `doubao-seed-2-0-code-preview-260215`.

If the user also needs WSL-local state fixed, repeat the same backup and update with `TARGET_HOME="$HOME"` or use `bash scripts/cc-switch-run.sh --wsl ...`; otherwise leave WSL-local alone.

## CLI Upgrade or WSL-Local Startup Hangs

Use this path when `cc-switch update` fixes GUI schema compatibility but raw WSL-local commands such as `HOME=/home/<user> cc-switch provider current -a claude` hang with no output.

Diagnosis:

```bash
ps -ef | rg 'cc-switch|cc-switch-run|sqlite3' | rg -v 'rg' || true
find ~/.cc-switch -maxdepth 1 \( -name '*-wal' -o -name '*-shm' -o -name '*.lock' \) -printf '%p %s bytes\n'
sqlite3 ~/.cc-switch/cc-switch.db 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA quick_check;'
```

Recovery:

- Kill only stale cc-switch validation processes that you started during this repair.
- Remove empty stale `cc-switch.db.init.lock` files after confirming no cc-switch process is using that HOME.
- Remove `cc-switch.db-wal` and `cc-switch.db-shm` only after a successful `wal_checkpoint(TRUNCATE)` and no live cc-switch process.
- If the real WSL HOME still hangs but a copied temp HOME works, back up `~/.cc-switch/settings.json` and replace it with the already-working GUI settings; this preserves the DB and avoids a downgrade.

Commands:

```bash
ps -ef | rg 'cc-switch' | rg -v 'rg' || true
sqlite3 ~/.cc-switch/cc-switch.db 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA quick_check;'
rm -f ~/.cc-switch/cc-switch.db.init.lock ~/.cc-switch/cc-switch.db-wal ~/.cc-switch/cc-switch.db-shm

TS=$(date +%Y%m%d-%H%M%S)
cp ~/.cc-switch/settings.json ~/.cc-switch/backups/settings.wsl.before-ccswitch-startup-fix-$TS.json
cp /mnt/c/Users/<WindowsUser>/.cc-switch/settings.json ~/.cc-switch/settings.json
chmod 600 ~/.cc-switch/settings.json

HOME="$HOME" timeout 30s cc-switch provider current -a claude
HOME="$HOME" cc-switch config validate
```

Do not downgrade the CLI after it migrates a database to a newer schema unless you have verified the older binary can still read that schema. Prefer repairing settings/locks first.

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
# Compare WSL and Windows cc-switch databases and print the shared target
bash scripts/cc-switch-run.sh doctor

# List providers from the shared GUI-backed cc-switch database while running in WSL
bash scripts/cc-switch-run.sh provider list

# Validate provider counts for the shared GUI-backed database
bash scripts/cc-switch-run.sh config validate

# List only Codex providers from the shared GUI-backed database
bash scripts/cc-switch-run.sh --app codex provider list

# Show the current Claude provider from the shared GUI-backed database
bash scripts/cc-switch-run.sh --app claude provider current

# Switch a shared GUI-backed provider
bash scripts/cc-switch-run.sh --app codex provider switch <provider-id>

# Print the HOME used by default/--gui, useful for long-running proxy commands
bash scripts/cc-switch-run.sh --gui print-home

# Add a provider to the WSL-local database explicitly
bash scripts/cc-switch-run.sh --wsl --app codex provider add

# Inspect an isolated worker home
bash scripts/cc-switch-run.sh --home /home/zhanxp/.agents/bdcc1 --app claude provider current

# Switch bdcc1's underlying Claude Code provider to Baidu Qianfan
HOME=/home/zhanxp/.agents/bdcc1 cc-switch provider switch -a claude baidu-qianfan
HOME=/home/zhanxp/.agents/bdcc1 cc-switch provider list -a claude

# Start the local cc-switch proxy in tmux; proxy serve is foreground by design
GUI_HOME="$(bash scripts/cc-switch-run.sh --gui print-home)"
HOME="$GUI_HOME" cc-switch proxy show
tmux new-session -d -s cc-switch-proxy \
  "HOME='$GUI_HOME' cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log"
HOME="$GUI_HOME" cc-switch proxy show

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
GUI_HOME="$(bash scripts/cc-switch-run.sh --gui print-home)"
HOME="$GUI_HOME" cc-switch proxy show
tmux has-session -t cc-switch-proxy || \
  tmux new-session -d -s cc-switch-proxy \
    "HOME='$GUI_HOME' cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log"
HOME="$GUI_HOME" cc-switch proxy show
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
GUI_HOME="$(bash scripts/cc-switch-run.sh --gui print-home)"
HOME="$GUI_HOME" cc-switch proxy show
tmux has-session -t cc-switch-proxy || \
  tmux new-session -d -s cc-switch-proxy \
    "HOME='$GUI_HOME' cc-switch proxy serve --listen-address 127.0.0.1 --listen-port 15721 2>&1 | tee -a logs/runtime/cc-switch-proxy.log"

# Once Claude is using http://127.0.0.1:15721, this changes the next proxied request.
bash scripts/cc-switch-run.sh --app claude provider switch baidu-qianfan
HOME="$GUI_HOME" cc-switch proxy show
```

If an existing terminal was opened before proxy routing was configured, explain that one restart is required to enter proxy mode; after that, future provider switches can be hot.

## Mismatch Handling

When CLI and GUI disagree, first assume the skill or raw CLI was pointed at a different home than the GUI. The skill wrapper is designed to prevent this by default:

- `bash scripts/cc-switch-run.sh ...` defaults to the Windows GUI home when it exists.
- `cc-switch ...` run raw in WSL still defaults to `/home/<user>/.cc-switch`; avoid raw `cc-switch` for normal user-facing actions.
- Use `bash scripts/cc-switch-run.sh --gui print-home` to see the exact shared operation object.
- Use `--wsl` only when the user explicitly asks for WSL-local state.

If raw `cc-switch provider list` says `No providers found` but the Windows app clearly shows providers, rerun the same command through this skill wrapper or `doctor`.

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
