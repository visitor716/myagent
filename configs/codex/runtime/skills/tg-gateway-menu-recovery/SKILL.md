---
name: tg-gateway-menu-recovery
description: Diagnose and fix tg-agent-gateway Telegram menu or command-bar no-response incidents, including /menu not returning, Telegram bottom menu clicks doing nothing, Gateway restart but bot inactive, Telegraf launch/polling hangs, tmux restart scripts losing proxy environment, setMyCommands/setChatMenuButton failures, callback_data drift such as back_to_main vs back_to_menu, and launchAsBot worker token polling conflicts. Use when working in /home/zhanxp/projects/tg-agent-gateway on Telegram Bot UI, manager bot startup, restart scripts, or mobile menu recovery.
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

3. **Telegraf launch semantics**
   - In long polling mode, `bot.launch()` does not normally resolve; it waits in the polling loop.
   - Do not block downstream startup forever by `await bot.launch()` for manager and then starting webapp/workers afterward.
   - Use the launch callback or a wrapper that resolves after `onLaunch` fires, then keep the polling promise observed for unexpected failure.

4. **Telegram menu configuration**
   - Configure command menu after the manager bot is proven running, not before launch blocks startup.
   - Use both:

```ts
bot.telegram.setMyCommands(commands)
bot.telegram.setChatMenuButton({ menuButton: { type: 'commands' } })
```

   - Add retry/backoff because Telegram API/proxy is often transient.
   - Also repair private chat menu with `ctx.setChatMenuButton({ type: 'commands' })` after admin auth; default menu config may not override an old chat-specific menu button.

5. **Callback route drift**
   - Search all callback ids:

```bash
rg -n "back_to_main|back_to_menu|menu:main|setChatMenuButton|setMyCommands|launchAsBot|bot.launch" src tests scripts
```

   - Standardize main-menu return buttons on `back_to_menu`.
   - Keep compatibility routes for old in-flight buttons, e.g. `back_to_main`, until old Telegram messages age out.

6. **Main-menu send lock**
   - If logs show `Main menu request ignored because another send is in flight`, the first `/menu` send is still pending.
   - Treat this as a stuck Telegram API call, not user error.
   - Wrap main-menu `reply`, `editMessageText`, and fallback sends with a bounded timeout so the in-flight lock is released and later `/menu` attempts can recover.
   - Log successful `Main menu sent` / `Main menu message edited` events; absence of those after a request means the send path is still blocked.

7. **Worker bot token conflicts**
   - `launchAsBot` workers must use their own configured token via `getBotToken(config.tokenEnv)`.
   - Never launch worker bots with `MANAGER_BOT_TOKEN`; that can create 409 polling conflicts and make the manager appear unresponsive.

## Safe Fix Pattern

Prefer this sequence for code changes:

1. Fix the runtime environment first: tmux/restart script proxy forwarding.
2. Add a Telegraf launch wrapper that retries startup and returns after the launch callback, not after polling stops.
3. Move `setupManagerBotCommands` to run after manager launch success.
4. Add per-chat menu repair in the admin middleware.
5. Fix callback compatibility (`back_to_main` -> `back_to_menu`).
6. Add a bounded timeout around main-menu Telegram sends if the menu in-flight lock can stick.
7. Fix worker bot token selection if workers are launched as bots.

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

Do not commit or push unless explicitly requested.
