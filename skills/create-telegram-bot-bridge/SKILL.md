---
name: create-telegram-bot-bridge
description: Use when the user wants to create a fresh Telegram bot for Claude-to-IM, rotate the Telegram bot token, or rebind the bridge to a new Telegram bot and verify the bridge end-to-end. This skill drives BotFather or Telegram Web, resolves the private chat_id, updates ~/.claude-to-im/config.env, optionally restarts the bridge, and validates the new bot.
---

# Create Telegram Bot Bridge

This skill turns Telegram bot rotation for `claude-to-im` into a repeatable workflow.
It covers browser takeover, BotFather creation, token and chat-id capture, bridge config rewrite, restart, and end-to-end verification.

## Use This Skill For

- "新建一个 Telegram bot 并切到 Claude-to-IM"
- "换一个新的 bot token 重新桥接"
- "帮我把桥接改绑到新的 Telegram bot"
- "Create a fresh Telegram bot and point Claude-to-IM at it"

## Do Not Use This Skill For

- Writing Telegram bots with SDKs such as Telegraf or grammY
- Building webhook handlers
- General Telegram Bot API programming questions
- Non-Telegram `claude-to-im` channels such as Discord, Feishu, QQ, or Weixin

## Workflow

### 1. Preflight

- Confirm `~/.claude-to-im/config.env` exists.
- Read the current bridge status before changing anything.
- Treat bot tokens as secrets. Mask them in updates and final output unless the user explicitly asks for the full token.
- Prefer keeping the same Telegram account as the destination unless the user says otherwise.

### 2. Get a Controllable Telegram Session

Choose the lightest path that still finishes the task:

- Reuse an existing Playwright-controlled Telegram Web session if one is already logged in.
- If the user wants to reuse a Windows Chrome login session from WSL, read [references/windows-chrome-cdp.md](/home/zhanxp/projects/myagent/skills/create-telegram-bot-bridge/references/windows-chrome-cdp.md).
- If no controllable session exists, open Telegram Web and have the user scan the QR code once, then continue automatically.

### 3. Create the Bot in BotFather

- Open `@BotFather`
- Send `/newbot`
- Choose a display name
- Choose a username ending with `bot`
- If BotFather rejects the username, retry with a shorter or less common variant
- Capture:
  - final bot username
  - HTTP API token

When parsing BotFather replies:

- Prefer the newest successful "Done! Congratulations..." block
- Extract the token from the code-style token line
- Do not assume the first token on screen is the newest one

### 4. Resolve the Private Chat ID

- Open the new bot chat
- Send `/start`
- If `getUpdates` is empty, send one more plain text message such as `bridge test from new bot`
- Resolve the private `chat_id` with `https://api.telegram.org/bot<TOKEN>/getUpdates`
- If an existing `CTI_TG_CHAT_ID` is present, compare it and only keep the old value if it still matches the intended account

### 5. Update Bridge Config

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

### 6. Restart and Verify

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
