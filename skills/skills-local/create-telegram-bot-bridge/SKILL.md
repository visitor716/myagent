---
name: create-telegram-bot-bridge
description: Use when the user wants to create a fresh Telegram bot for Claude-to-IM, rotate the Telegram bot token, rebind the bridge to a new Telegram bot, or clean up a mistakenly-created BotFather bot. This skill drives BotFather or Telegram Web, resolves the private chat_id, updates ~/.claude-to-im/config.env, optionally restarts the bridge, validates the new bot, and safely deletes mistaken bots only through a guarded script.
---

# Create Telegram Bot Bridge

This skill turns Telegram bot rotation for `claude-to-im` into a repeatable workflow.
It covers browser takeover, BotFather creation, token and chat-id capture, bridge config rewrite, restart, and end-to-end verification.

## Use This Skill For

- "新建一个 Telegram bot 并切到 Claude-to-IM"
- "换一个新的 bot token 重新桥接"
- "帮我把桥接改绑到新的 Telegram bot"
- "删除刚才误创建的 Telegram bot"
- "清理 BotFather 里命名不合规的 bot"
- "Create a fresh Telegram bot and point Claude-to-IM at it"

## Do Not Use This Skill For

- Writing Telegram bots with SDKs such as Telegraf or grammY
- Building webhook handlers
- General Telegram Bot API programming questions
- Non-Telegram `claude-to-im` channels such as Discord, Feishu, QQ, or Weixin
- Ad-hoc browser automation for BotFather deletion when the bundled cleanup script applies

## Workflow

### 1. Preflight

- Confirm `~/.claude-to-im/config.env` exists.
- Read the current bridge status before changing anything.
- Treat bot tokens as secrets. Mask them in updates and final output unless the user explicitly asks for the full token.
- Prefer keeping the same Telegram account as the destination unless the user says otherwise.
- Treat bot display names and usernames as public identifiers. Do not derive them from local machine/user identity.

### 2. Get a Controllable Telegram Session

Choose the lightest path that still finishes the task:

- Reuse an existing Playwright-controlled Telegram Web session if one is already logged in.
- If the user wants to reuse a Windows Chrome login session from WSL, read [references/windows-chrome-cdp.md](/home/zhanxp/projects/myagent/skills/create-telegram-bot-bridge/references/windows-chrome-cdp.md).
- If no controllable session exists, open Telegram Web and have the user scan the QR code once, then continue automatically.
- If Telegram Web is already logged in and reachable through CDP or a stable automation session, complete the BotFather flow yourself. Do not ask the user to manually create the bot or paste the token unless login, 2FA, captcha, or an unavailable browser session is the actual blocker.

### 3. Create the Bot in BotFather

- Open `@BotFather`
- Send `/newbot`
- Choose a display name
- Choose a username ending with `bot`
- If BotFather rejects the username, retry with a shorter or less common variant
- Capture:
  - final bot username
  - HTTP API token

Naming privacy rules:

- Never include a personal name, local username, home-directory basename, machine hostname, email handle, repo owner, or private organization/customer identifier in the bot display name or username unless the user explicitly requests that exact public branding.
- Before sending a candidate username to BotFather, run a quick privacy lint: reject it if it contains `$USER`, `$USERNAME`, `$LOGNAME`, the basename of `$HOME`, or any user-provided forbidden substring.
- Prefer neutral, role-based names such as `cc6_agent_bot`, `cc6_worker_bot`, `gateway_cc6_bot`, or `<project>_<role>_bot` when no public brand namespace is supplied.
- If a bot was accidentally created with a sensitive username during the same workflow, do not configure it. Create a replacement with a privacy-safe username, revoke/delete the mistaken bot only when the task explicitly asks for cleanup or when it is clearly safe to select that exact bot in BotFather, and report the cleanup status without printing tokens.
- When retrying after a bad username, reuse the proven automation path from the successful attempt but swap in privacy-safe candidates; do not fall back to a human handoff just because one helper command such as `playwright-cli attach` is flaky while raw CDP or another controlled path is available.

When parsing BotFather replies:

- Prefer the newest successful "Done! Congratulations..." block
- Extract the token from the code-style token line
- Do not assume the first token on screen is the newest one
- Tie the token to the intended bot username. If the token appears before the intended username in the transcript, or matches any existing token, treat it as stale and recapture from the latest successful BotFather block.
- Do not print raw tokens to stdout, screenshots, logs, final replies, or tracked files. Write tokens only to the intended secret config file or a temporary file with mode `0600`, then remove the temporary file after use.

### 4. Clean Up a Mistaken Bot

Use this path when the task is to delete a bot that was created by mistake, especially after a naming-privacy failure.

Do not hand-write BotFather browser automation for this. Run the guarded script:

```bash
TARGET_BOT_USERNAME='@mistaken_bot' \
ACTIVE_BOT_USERNAME='@known_good_bot' \
BOT_DISPLAY_NAME='Expected Display Name' \
bash scripts/delete_botfather_bot_via_cdp.sh --dry-run
```

Only delete after dry-run confirms a unique target and the still-valid active bot is not the target:

```bash
TARGET_BOT_USERNAME='@mistaken_bot' \
ACTIVE_BOT_USERNAME='@known_good_bot' \
BOT_DISPLAY_NAME='Expected Display Name' \
bash scripts/delete_botfather_bot_via_cdp.sh --confirm-delete
```

Cleanup rules:

- The script defaults to dry-run; deletion requires `--confirm-delete`.
- Prefer `TARGET_BOT_USERNAME_FILE=/path/to/0600-file` when the mistaken username should not appear in shell history, tmux panes, or tool transcripts.
- Always set `ACTIVE_BOT_USERNAME` for the bot that must survive, when one exists.
- If the script reports `target_count` other than `1`, stop. Do not guess from visible chat history.
- If the script cannot confirm the final BotFather deletion prompts still name the target bot, stop.
- After deletion, verify `/mybots` no longer lists the target and still lists the active bot.
- Keep outputs masked; do not print raw tokens or the mistaken username in final reports.

### 5. Resolve the Private Chat ID

- Open the new bot chat
- Send `/start`
- If `getUpdates` is empty, send one more plain text message such as `bridge test from new bot`
- Resolve the private `chat_id` with `https://api.telegram.org/bot<TOKEN>/getUpdates`
- If an existing `CTI_TG_CHAT_ID` is present, compare it and only keep the old value if it still matches the intended account

### 6. Update Bridge Config

Use [scripts/update_telegram_bridge.py](/home/zhanxp/projects/myagent/skills/create-telegram-bot-bridge/scripts/update_telegram_bridge.py) to update:

- `CTI_ENABLED_CHANNELS`
- `CTI_TG_BOT_TOKEN`
- `CTI_TG_CHAT_ID`
- optional `CTI_TG_ALLOWED_USERS`

Rules:

- Preserve unrelated config keys
- Preserve comments when practical, but correctness matters more than comment retention
- Set file mode to `0600`
- Validate the token with `getMe` before declaring success

### 7. Restart and Verify

- If the user wants the bridge running immediately, restart it through `claude-to-im/scripts/daemon.sh`
- Check daemon status
- Send a real Telegram message through the new bot and verify the bridge responds
- Report:
  - bot username
  - masked token
  - resolved chat id
  - whether the daemon was restarted
  - whether end-to-end messaging succeeded

## Operational Notes

- Canonical `claude-to-im` source lives under `/home/zhanxp/projects/myagent/skills/claude-to-im`
- `config.env` target is `~/.claude-to-im/config.env`
- Token validation reference: `claude-to-im/references/token-validation.md`
- If browser reuse from Windows is needed, the helper relay scripts in `scripts/` can expose Windows Chrome CDP to WSL

## Recovery Rule

If this skill is missing from runtime paths, restore it from:

- `/home/zhanxp/projects/myagent/skills/create-telegram-bot-bridge`

Runtime entrypoints should only be symlinks back to that directory.
