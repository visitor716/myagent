# WebApp URL Monitor

Operate and maintain the `tg-agent-gateway` WebApp public URL monitor implemented by `scripts/monitor-webapp-url.sh`. Use this lane for monitor lifecycle, rotation, and threshold questions. For symptom-first incident triage (menu dead, blank WebApp, stale iframe, tunnel pointing at Vite), start with `runtime-recovery.md` instead and come back here when the fix is "rotate or repair the public URL".

## What It Checks

The monitor validates the current `TG_WEBAPP_URL` against the real WebApp path:

- Local health: `http://127.0.0.1:${WEBAPP_PORT:-3000}/health` returns JSON with `status: "ok"`.
- Public HTML: the current `TG_WEBAPP_URL` returns production HTML — not a Cloudflare error page, not Vite dev HTML, not a stale tunnel error.
- Public asset: the referenced `/assets/index-*.js` downloads successfully.

If local health is good but the public URL stays unhealthy for `WEBAPP_URL_MONITOR_FAILURE_SECONDS`, the script rotates the Cloudflare quick tunnel, writes the new URL into `.env`, runs `scripts/restart-gateway.sh`, and publishes a refreshed WebApp entry.

## Commands

Run from `/home/zhanxp/projects/tg-agent-gateway`:

```bash
npm run webapp:url-monitor          # single check
npm run webapp:url-monitor:start    # background tmux monitor
npm run webapp:url-monitor:status   # current state
npm run webapp:url-monitor:stop
```

Dry-run rotation without touching the live tunnel:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate --dry-run
```

Real rotation — only when the user explicitly asks for it or public health is already broken:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate
```

## Configuration

Set in `.env` (defaults mirrored in `.env.example`):

```text
WEBAPP_PORT=3000
WEBAPP_URL_MONITOR_INTERVAL_SECONDS=300
WEBAPP_URL_MONITOR_FAILURE_SECONDS=3600
WEBAPP_URL_MONITOR_AUTO_ROTATE=1
WEBAPP_URL_MONITOR_NEW_URL_READY_ATTEMPTS=18
# CLOUDFLARED_BIN=/home/zhanxp/.local/bin/cloudflared
```

Use `CLOUDFLARED_BIN` when the default binary lookup fails.

## Recovery Workflow

When the user says the App cannot open or the URL expired:

1. `npm run webapp:url-monitor:status`
2. `npm run webapp:url-monitor` for a fresh check.
3. If the current URL is healthy, the URL is not the problem — send a fresh entry, because old Telegram buttons keep their old URL:

```bash
npm run notify:webapp-release -- --force
```

4. If the public URL is failing and the user needs immediate recovery, do a real forced rotation:

```bash
bash scripts/monitor-webapp-url.sh --once --force-rotate
```

5. After rotation, re-check status and tell the user to close old Telegram WebApp popups before tapping the newest button.

## Cellular / WiFi Split

When the App opens on phone WiFi but hangs on cellular/5G behind Telegram's native four-square loader:

1. Local `/health` or a desktop `curl` success is not sufficient. The carrier path to `trycloudflare.com` can fail while WSL and desktop browsers still work.
2. Send a fresh cache-busted button first, then look for iPhone requests in Gateway logs if document/probe logging exists.
3. If the iPhone never requests the current URL — or requests HTML/assets but stays on the native loader — stop blind quick-tunnel rotation and move toward a Cloudflare named tunnel / custom hostname.
4. For a temporary proof only, an alternate HTTPS tunnel (Serveo) may be started and used solely after verifying it serves production HTML and `/assets/index-*.js` directly:

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

5. After switching `.env` `TG_WEBAPP_URL`, run `scripts/restart-gateway.sh`, then `npm run webapp:url-monitor` to clear stale failure state and publish a fresh entry.

## Safety Rules

- Do not change Telegram command semantics, callback data, worker config, or task-status behavior while operating the monitor.
- Do not rotate while local `/health` is down — restart Gateway first instead of hiding a local outage behind a tunnel change.
- Do not treat a live `cloudflared` process as proof the public URL works; prove public HTML and the production JS asset.
- Do not keep Serveo or any anonymous tunnel as the durable fix — use it only to prove carrier/tunnel incompatibility.
- Prefer a Cloudflare named tunnel with a fixed hostname for anything durable. This monitor is a quick-tunnel recovery layer, not a replacement for a named tunnel.

## Verification

After changing the monitor script or this lane:

```bash
bash -n scripts/monitor-webapp-url.sh
npm run webapp:url-monitor
npm run webapp:url-monitor:status
npm run type-check
npm run build
```

For threshold state-machine work, use a temporary env with a low threshold plus `--dry-run`; do not break the real tunnel to test.
