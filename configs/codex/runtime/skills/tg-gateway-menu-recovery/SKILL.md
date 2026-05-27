---
name: tg-gateway-menu-recovery
description: Diagnose and fix tg-agent-gateway Telegram menu, command-bar, or mobile WebApp no-response incidents, including /menu not returning, Telegram bottom menu clicks doing nothing, phone WebApp blank/no UI, stale Telegram WebApp popups pointing at old Cloudflare quick tunnels, WebApp URL or tunnel target drift, Gateway restart but bot inactive, Telegraf launch/polling hangs, tmux restart scripts losing proxy environment, setMyCommands/setChatMenuButton failures, callback_data drift such as back_to_main vs back_to_menu, and launchAsBot worker token polling conflicts. Use when working in /home/zhanxp/projects/tg-agent-gateway on Telegram Bot UI, WebApp entry, manager bot startup, restart scripts, or mobile menu recovery.
---

# TG Gateway Menu Recovery

Use this skill to recover tg-agent-gateway when Telegram appears alive in code but the phone UI does not respond. Treat "menu does nothing" as a runtime-path problem until logs prove callback routing is the culprit.

## First Checks

1. Confirm the repository and worktree state:

```bash
pwd
git status --short
```

2. Run the bundled runtime snapshot when available:

```bash
bash ~/.codex/skills/tg-gateway-menu-recovery/scripts/check-runtime.sh
```

3. Read fresh runtime evidence before editing code:

```bash
tail -n 120 logs/runtime/gateway.log
tail -n 80 logs/tg-gateway-$(date +%F).log 2>/dev/null || true
tmux capture-pane -pt tg-agent-gateway -S -100 2>/dev/null || true
ps -ef | rg "node dist/index|tsx src/index|tg-agent-gateway" | rg -v "rg|claude"
```

## Diagnosis Order

1. **Bot process actually running**
   - If logs stop at `Starting Telegram bot...` without `Telegram bot is running`, the menu cannot respond.
   - If logs show `Fatal startup error` with `getMe`, `setMyCommands`, or `network timeout`, treat startup/network as the root path.
   - If tmux exists but there is no `node dist/index.js`, the tmux session is stale, not a running Gateway.

2. **Proxy environment inside tmux**
   - Compare current shell proxy env with the running Gateway process env:

```bash
env | rg '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy)='
pid=$(pgrep -f 'node dist/index.js' | head -n1)
tr '\0' '\n' < "/proc/$pid/environ" | rg '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy)='
```

   - If manual `getMe` works with proxy but Gateway has no proxy env, fix `scripts/restart-gateway.sh` so tmux receives the proxy exports.
   - Do not put tokens in logs. It is acceptable to log proxy host/port without credentials.

3. **Mobile WebApp URL and tunnel target**
   - If the phone WebApp opens to a blank/no-UI page after restart, verify the actual URL path before changing React code.
   - `TG_WEBAPP_URL` is the button target for new `/start` messages; old Telegram messages keep their old inline-button URL.
   - Telegram clients can also keep an already-open WebApp popup/iframe. After a quick-tunnel rotation, that stale iframe may still point at the old `*.trycloudflare.com` URL and show `530 The origin has been unregistered from Argo Tunnel`.
   - Direct desktop Chrome can prove the tunnel serves HTML, but it is not enough: outside Telegram it may show `Not running in Telegram WebApp`, and it does not prove what URL the Telegram popup is actually loading.
   - In this project, production WebApp is served by Gateway on `WEBAPP_PORT` / `localhost:3000`; Vite dev is `5173`.
   - A Cloudflare quick tunnel pointing at `localhost:5173` can work in desktop Chrome but show a blank/no-UI page in Telegram mobile WebView because it serves Vite HMR/dev modules.
   - Probe the target split:

```bash
node -e "require('dotenv').config(); for (const k of ['TG_WEBAPP_URL','WEBAPP_PORT']) console.log(k+'='+(process.env[k]||''))"
ps -ef | rg "cloudflared|vite|node dist/index" | rg -v "rg|claude"
ss -ltnp | rg ':(3000|5173|5174|20241)\b|cloudflared|node'
tmux capture-pane -pt tg-webapp-tunnel -S -120 2>/dev/null || true
curl -sS -m 20 "$TG_WEBAPP_URL/" -o /tmp/tg-webapp.html
rg -n "@vite/client|/src/main|/assets/" /tmp/tg-webapp.html
```

   - Healthy production HTML references `/assets/index-*.js` and does not reference `@vite/client` or `/src/main`.
   - If using Telegram Web for proof, use the `wsl-windows-chrome` skill first, select the logged-in Telegram Web tab, close any old WebApp popup, click the newest fresh button, then inspect iframe URLs:

```bash
bash /home/zhanxp/.agents/skills/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --status --json
playwright-cli -s=tg-mobile-debug tab-list
playwright-cli -s=tg-mobile-debug tab-select <telegram-tab-index>
playwright-cli -s=tg-mobile-debug snapshot
playwright-cli -s=tg-mobile-debug run-code "async page => ({ frames: page.frames().map(f => f.url()), text: (await page.locator('body').innerText()).slice(-1200) })"
```

   - Healthy Telegram proof: the WebApp iframe URL starts with the current `TG_WEBAPP_URL`, the snapshot shows app content such as `当前项目` / bottom navigation, and the page does not contain the Cloudflare 530 text.
   - If `cloudflared` settings show `url:http://localhost:5173`, recreate the tunnel to `http://localhost:3000`, update `.env`, restart Gateway, then send a fresh button.

```bash
tmux kill-session -t tg-webapp-tunnel 2>/dev/null || true
pkill -f 'cloudflared tunnel --url http://localhost:5173' 2>/dev/null || true
tmux new-session -d -s tg-webapp-tunnel "cd /home/zhanxp/projects/tg-agent-gateway && /home/zhanxp/.local/bin/cloudflared tunnel --url http://localhost:3000 --no-autoupdate"
sleep 10
tmux capture-pane -pt tg-webapp-tunnel -S -80
```

   - Copy the new `https://*.trycloudflare.com` URL into `.env` as `TG_WEBAPP_URL`, run `scripts/restart-gateway.sh`, and send a fresh `/start` or direct WebApp button. Tell the user to close old WebApp popups first and not to tap old inline buttons.

4. **Telegraf launch semantics**
   - In long polling mode, `bot.launch()` does not normally resolve; it waits in the polling loop.
   - Do not block downstream startup forever by `await bot.launch()` for manager and then starting webapp/workers afterward.
   - Use the launch callback or a wrapper that resolves after `onLaunch` fires, then keep the polling promise observed for unexpected failure.

5. **Telegram menu configuration**
   - Configure command menu after the manager bot is proven running, not before launch blocks startup.
   - Use both:

```ts
bot.telegram.setMyCommands(commands)
bot.telegram.setChatMenuButton({ menuButton: { type: 'commands' } })
```

   - Add retry/backoff because Telegram API/proxy is often transient.
   - Also repair private chat menu with `ctx.setChatMenuButton({ type: 'commands' })` after admin auth; default menu config may not override an old chat-specific menu button.

6. **Callback route drift**
   - Search all callback ids:

```bash
rg -n "back_to_main|back_to_menu|menu:main|setChatMenuButton|setMyCommands|launchAsBot|bot.launch" src tests scripts
```

   - Standardize main-menu return buttons on `back_to_menu`.
   - Keep compatibility routes for old in-flight buttons, e.g. `back_to_main`, until old Telegram messages age out.

7. **Main-menu send lock**
   - If logs show `Main menu request ignored because another send is in flight`, the first `/menu` send is still pending.
   - Treat this as a stuck Telegram API call, not user error.
   - Wrap main-menu `reply`, `editMessageText`, and fallback sends with a bounded timeout so the in-flight lock is released and later `/menu` attempts can recover.
   - Log successful `Main menu sent` / `Main menu message edited` events; absence of those after a request means the send path is still blocked.

8. **Worker bot token conflicts**
   - `launchAsBot` workers must use their own configured token via `getBotToken(config.tokenEnv)`.
   - Never launch worker bots with `MANAGER_BOT_TOKEN`; that can create 409 polling conflicts and make the manager appear unresponsive.

## Safe Fix Pattern

Prefer this sequence for code changes:

1. Fix the runtime environment first: tmux/restart script proxy forwarding.
2. For phone WebApp blank/no UI, fix the tunnel target and WebApp URL before changing frontend code.
3. Before changing React for a mobile blank screen, close stale Telegram WebApp popups, click a timestamped fresh button, and prove the iframe URL plus rendered app content.
4. Add a Telegraf launch wrapper that retries startup and returns after the launch callback, not after polling stops.
5. Move `setupManagerBotCommands` to run after manager launch success.
6. Add per-chat menu repair in the admin middleware.
7. Fix callback compatibility (`back_to_main` -> `back_to_menu`).
8. Add a bounded timeout around main-menu Telegram sends if the menu in-flight lock can stick.
9. Fix worker bot token selection if workers are launched as bots.

Keep changes small and testable. Avoid changing Telegram command semantics, callback formats beyond compatibility aliases, task status semantics, or workspace paths.

## Verification

Run standard checks:

```bash
npm run type-check
npm run build
npm run test:unit
```

Then restart and prove runtime success:

```bash
scripts/restart-gateway.sh
sleep 8
tail -n 80 logs/runtime/gateway.log
```

Required evidence:

- `Using proxy: ...` appears when proxy is needed.
- `Telegram bot is running { botId: 'manager' ... }`
- `=== Gateway started successfully ===`
- `Telegram bot commands configured`
- `Telegram default menu button configured`
- If recovering mobile WebApp, `TG_WEBAPP_URL` points to the current tunnel and the tunnel settings show `url:http://localhost:3000`.
- Current WebApp HTML references production `/assets/index-*.js`, not Vite `@vite/client` or `/src/main`.
- Telegram WebApp iframe, when checked through Telegram Web, points at the current `TG_WEBAPP_URL`, not an old `*.trycloudflare.com` URL, and the snapshot shows app UI such as `当前项目`.
- WebApp API calls such as `/api/webapp/projects` and `/api/webapp/dashboard` return `200` when opened with valid Telegram WebApp `initData`.
- `/menu` attempts either log `Main menu sent` / `Main menu message edited`, or a bounded timeout error followed by a released in-flight lock.
- Worker bots do not log manager-token placeholder use.

If those appear and the user still reports no menu response, ask them to send `/menu` once from the same private chat. That update should trigger the chat-specific menu repair log:

```text
Private chat menu button configured
```

## Useful Probes

Check Telegram API through the same proxy without printing the token:

```bash
node --input-type=module -e "import 'dotenv/config'; import fetch from 'node-fetch'; import { HttpsProxyAgent } from 'https-proxy-agent'; const token=process.env.MANAGER_BOT_TOKEN; const proxy=process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy; const started=Date.now(); const res=await fetch('https://api.telegram.org/bot'+token+'/getMe',{agent: proxy ? new HttpsProxyAgent(proxy) : undefined, timeout:15000}); const json=await res.json(); console.log('status='+res.status,'ok='+json.ok,'username='+(json.result?.username ?? ''),'ms='+(Date.now()-started));"
```

Check Telegraf with the project proxy agent:

```bash
node --import tsx --input-type=module -e "import 'dotenv/config'; import { Telegraf } from 'telegraf'; import { getProxyAgent } from './src/telegram/botInitializer.ts'; const bot = new Telegraf(process.env.MANAGER_BOT_TOKEN,{telegram:{agent:getProxyAgent()}}); const started=Date.now(); const me=await bot.telegram.getMe(); console.log('ms='+(Date.now()-started),'username='+me.username);"
```

Send a fresh WebApp button after changing `TG_WEBAPP_URL`; this avoids stale inline buttons that still point to the old quick tunnel:

```bash
node --input-type=module <<'NODE'
import 'dotenv/config';
import fetch from 'node-fetch';
import { HttpsProxyAgent } from 'https-proxy-agent';

const token = process.env.MANAGER_BOT_TOKEN;
const chatId = process.env.ADMIN_USER_ID;
const webappUrl = process.env.TG_WEBAPP_URL;
const proxy = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy;
if (!token || !chatId || !webappUrl) throw new Error('missing env');
const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
  method: 'POST',
  agent: proxy ? new HttpsProxyAgent(proxy) : undefined,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    chat_id: chatId,
    text: `最新 WebApp 入口（${new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })}）：请先关闭旧弹窗，再点下面按钮。`,
    reply_markup: { inline_keyboard: [[{ text: '打开最新控制台', web_app: { url: webappUrl } }]] },
  }),
});
const data = await res.json();
console.log(JSON.stringify({ ok: data.ok, status: res.status, messageId: data.result?.message_id }, null, 2));
NODE
```

Do not commit or push unless explicitly requested.
