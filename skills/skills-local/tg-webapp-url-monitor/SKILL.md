---
name: my-tg-webapp-url-monitor
description: Operate and maintain the tg-agent-gateway WebApp public URL monitor. Use when the user asks to monitor TG_WEBAPP_URL, detect expired trycloudflare links, auto-rotate stale WebApp URLs after sustained failure, start or stop the WebApp URL monitor, inspect monitor status, recover a broken Telegram WebApp entry, diagnose WiFi works but cellular/5G fails, or package the monitor/deploy flow as a reusable skill.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-tg-webapp-url-monitor` once near the start; if it fails, continue.

# TG WebApp URL Monitor

Use this skill in `/home/zhanxp/projects/tg-agent-gateway` to operate the WebApp public URL monitor added around `scripts/monitor-webapp-url.sh`.

## What It Does

The monitor checks the current `TG_WEBAPP_URL` against the actual WebApp path:

- Local health: `http://127.0.0.1:${WEBAPP_PORT:-3000}/health` must return JSON with `status: "ok"`.
- Public HTML: current `TG_WEBAPP_URL` must load production HTML, not Cloudflare error pages, Vite dev HTML, or stale tunnel errors.
- Public asset: the referenced `/assets/index-*.js` must return successfully.

If local health is good but the public URL stays unhealthy for `WEBAPP_URL_MONITOR_FAILURE_SECONDS` seconds, the script rotates the Cloudflare quick tunnel, writes the new URL into `.env`, runs `scripts/restart-gateway.sh`, and publishes a refreshed WebApp entry.

## Commands

Check once:

```bash
npm run webapp:url-monitor
```

Start the background tmux monitor:

```bash
npm run webapp:url-monitor:start
```

Inspect status:

```bash
npm run webapp:url-monitor:status
```

Stop the monitor:

```bash
npm run webapp:url-monitor:stop
```

Force a dry-run rotation without touching the live tunnel:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate --dry-run
```

Force a real rotation only when the user explicitly asks or public health is already broken:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate
```

## Defaults

These are configured in `.env` or `.env.example`:

```text
WEBAPP_PORT=3000
WEBAPP_URL_MONITOR_INTERVAL_SECONDS=300
WEBAPP_URL_MONITOR_FAILURE_SECONDS=3600
WEBAPP_URL_MONITOR_AUTO_ROTATE=1
```

Use `CLOUDFLARED_BIN=/path/to/cloudflared` if the default lookup does not find the binary.

## Recovery Workflow

When the user says the App cannot open or the URL expired:

1. Run `npm run webapp:url-monitor:status`.
2. Run `npm run webapp:url-monitor` for a fresh check.
3. If current URL is healthy, send a fresh App entry because old Telegram buttons keep old URLs:

```bash
npm run notify:webapp-release -- --force
```

4. If the public URL is failing and the user needs immediate recovery, run a real forced rotation:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate
```

5. After rotation, verify status and tell the user to close old Telegram WebApp popups before tapping the newest button.

## Cellular / WiFi Split

When the App opens on phone WiFi but hangs on cellular/5G with Telegram's native four-square loader:

1. Do not treat local `/health` or desktop `curl` success as sufficient. The mobile carrier path to `trycloudflare.com` can fail while WSL and desktop browsers still work.
2. Send a fresh cache-busted button first, then check for iPhone requests in Gateway logs if document/probe logging exists.
3. If the iPhone never requests the current URL, or it requests HTML/assets but stays on the native loader, stop blind quick-tunnel rotation. Prefer a Cloudflare named tunnel/custom hostname.
4. For a temporary proof, start an alternate HTTPS tunnel such as Serveo and only switch to it after verifying it serves production HTML and `/assets/index-*.js` directly:

```bash
tmux kill-session -t tg-webapp-serveo 2>/dev/null || true
: > logs/runtime/serveo-tunnel.log
tmux new-session -d -s tg-webapp-serveo "cd /home/zhanxp/projects/tg-agent-gateway && ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=10 -o ExitOnForwardFailure=yes -R 80:127.0.0.1:3000 serveo.net 2>&1 | tee -a logs/runtime/serveo-tunnel.log"
sleep 8
serveo_url="$(python3 - <<'PY'
from pathlib import Path
import re
text = re.sub(r'\x1b\[[0-9;]*m', '', Path('logs/runtime/serveo-tunnel.log').read_text(errors='ignore'))
match = re.search(r'https://\S+', text)
print(match.group(0) if match else '')
PY
)"
curl -sS -L -m 25 "$serveo_url/" -o /tmp/tg-webapp-serveo.html
rg -n "@vite/client|/src/main|/assets/index|Cloudflare|Warning|serveo" /tmp/tg-webapp-serveo.html
```

5. After switching `.env` `TG_WEBAPP_URL`, run `scripts/restart-gateway.sh`, then `npm run webapp:url-monitor` to clear stale failure state and publish/send a fresh entry.

## Safety Rules

- Do not edit Telegram command semantics, callback data, worker config, or task status behavior while operating this monitor.
- Do not rotate if local `/health` is down; restart Gateway first and avoid hiding a local server outage behind a tunnel change.
- Do not treat a live `cloudflared` process as proof that the public URL works; prove public HTML and the production JS asset.
- Do not keep Serveo or any anonymous tunnel as the durable fix. Use it only to prove carrier/tunnel incompatibility, then move to a named tunnel or fixed hostname.
- Prefer a Cloudflare named tunnel for a permanent fixed hostname. This monitor is a quick-tunnel recovery layer, not a substitute for named tunnel setup.

## Verification

After changing the monitor script or this skill, run:

```bash
bash -n scripts/monitor-webapp-url.sh
npm run webapp:url-monitor
npm run webapp:url-monitor:status
npm run type-check
npm run build
```

For the threshold state machine, use a temporary env and low threshold with `--dry-run`; do not break the real tunnel for a test.
