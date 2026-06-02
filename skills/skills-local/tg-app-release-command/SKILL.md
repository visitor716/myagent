---
name: tg-app-release-command
description: Implement, verify, or operate tg-agent-gateway `/app`, `/webapp`, and `/latest_app` commands so they send the latest WebApp entry to the Telegram bot with release version, branch-specific version fingerprint, branch name, deployment time, latest update notes, and fresh WebApp buttons. Use when the user asks to make `/app` send the latest app, include version/branch/deploy time/update content, make version change across branches, or diagnose stale WebApp release information.
---

# TG App Release Command

Use this skill in `/home/zhanxp/projects/tg-agent-gateway` when `/app` should be the authoritative WebApp release entry in Telegram.

## Required `/app` Contract

`/app`, `/webapp`, and `/latest_app` must use the same handler and return:

- App title: `TG Agent Gateway WebApp`.
- Version: include package version plus a branch-specific fingerprint, so the visible version changes when the branch changes even if `package.json` is unchanged.
- Branch: the actual current git branch, normally `master`.
- Deployment time: Asia/Shanghai time for the current deployed build/restart.
- Latest update content: concise release notes for the currently deployed app.
- Latest link: current `TG_WEBAPP_URL`.
- Buttons:
  - WebApp button to open the latest console.
  - Browser URL fallback.

Do not use a hardcoded `master` constant unless the runtime truly cannot read git. Prefer reading `git branch --show-current` and falling back to `master`.

## Version Rule

Use a deterministic display version:

```text
v<package.version>+<safe-branch>.<shortCommit>
```

Examples:

```text
v1.0.1+master.756faca
v1.0.1+wt-cc5.83e4571
```

Normalize branch names for version text with lowercase and non-alphanumeric runs replaced by `-`. This satisfies the invariant that a different branch produces a different version string.

## Deployment Time

Prefer a persisted deployment/release state written by `scripts/restart-gateway.sh` or `scripts/notify-webapp-release.ts`. If no state exists, use the current process start time or current time as a fallback, but label it as runtime time in code comments/tests only when needed.

Display time in Chinese locale with `Asia/Shanghai`, `hour12: false`.

## Latest Update Content

Use a short release-notes source in this order:

1. Explicit current release notes constant in `src/services/webappReleaseNotificationService.ts`.
2. Recent git commit subjects since the previous release state commit.
3. The current HEAD commit subject.

Keep the Telegram message compact; do not paste diffs or terminal logs.

## Implementation Pointers

Current relevant files:

- `src/telegram/commands/appCommand.ts`
- `src/services/webappReleaseNotificationService.ts`
- `scripts/notify-webapp-release.ts`
- `src/telegram/registerCommands.ts`
- `src/telegram/formatters/helpFormatter.ts`
- `tests/unit/appCommand.test.ts`
- `tests/unit/webappReleaseNotificationService.test.ts`

Prefer adding pure helpers in `webappReleaseNotificationService.ts` and unit-testing those helpers. Keep Telegram handler code thin.

## Fresh Bot Send

When the user explicitly asks to send the latest App to the bot, do not stop at `npm run notify:webapp-release` if it prints `SKIP: ... already notified ...`. Send a direct fresh button with a timestamped URL:

```bash
set -a; source .env; set +a
fresh_url=$(node --input-type=module -e "const u=new URL(process.env.TG_WEBAPP_URL); u.searchParams.set('v', Date.now().toString()); console.log(u.toString())")
text="最新 WebApp 入口（$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')）：请先关闭旧弹窗，再点下面按钮。"
body=$(node --input-type=module - "$ADMIN_USER_ID" "$text" "$fresh_url" <<'NODE'
const [chatId, text, freshUrl] = process.argv.slice(2);
console.log(JSON.stringify({
  chat_id: chatId,
  text,
  reply_markup: {
    inline_keyboard: [
      [{ text: '打开最新控制台', web_app: { url: freshUrl } }],
      [{ text: '浏览器打开链接', url: freshUrl }],
    ],
  },
}));
NODE
)
proxy="${HTTPS_PROXY:-${HTTP_PROXY:-http://127.0.0.1:4062}}"
curl -sS --proxy "$proxy" -H 'content-type: application/json' -d "$body" "https://api.telegram.org/bot${MANAGER_BOT_TOKEN}/sendMessage" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{const j=JSON.parse(s); console.log(JSON.stringify({ok:j.ok,messageId:j.result?.message_id,description:j.description},null,2));})"
```

If public `TG_WEBAPP_URL` fails before sending, switch to `tg-gateway-menu-recovery`: recreate the tunnel, update `.env`, restart Gateway, then send the fresh button.

## Verification

Run focused tests first:

```bash
MANAGER_BOT_TOKEN=dummy ADMIN_USER_ID=1 npx vitest run tests/unit/appCommand.test.ts tests/unit/webappReleaseNotificationService.test.ts
npm run type-check
npm run build
```

If frontend assets or runtime URL changed:

```bash
npm run webapp:build
bash scripts/restart-gateway.sh
curl -sS http://127.0.0.1:3000/health
```

For live bot verification, prove:

- `/app` message contains `版本：v...+<branch>.<shortCommit>`.
- It contains `分支：master` when running on master.
- It contains `部署时间：`.
- It contains `更新内容：`.
- It includes both WebApp and browser fallback buttons.

Do not commit or push unless explicitly requested.
