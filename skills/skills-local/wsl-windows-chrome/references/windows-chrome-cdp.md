# Windows Chrome CDP from WSL

Read this file when `scripts/attach_windows_logged_in_chrome.sh` cannot attach automatically and the task still needs the Windows-side automation browser.

## Goal

Attach from WSL to the dedicated Windows Chrome agent browser without logging in again inside a fresh Linux browser profile.

## Recommended Topology

Use a dedicated Windows browser instance:

- Start Windows Chrome, not a WSL/Linux browser
- Use fixed CDP port `9222`
- Use `--user-data-dir=C:\chrome-wsl-automation`
- Use `--profile-directory=Default`
- Keep reusing that same profile so cookies, storage, site permissions, and login state persist

Avoid pointing automation at the default day-to-day browser profile.
If port `9222` is occupied but does not answer `/json/version`, treat it as a conflict and fix the Windows process. Do not switch to another CDP port for normal agent browser automation.
If `DevToolsActivePort` is missing, the helper can fall back to the browser process command line for diagnostics, but the expected port remains `9222`.

## Expected Windows-side State

- Windows Chrome is already running.
- Remote debugging is enabled on the target browser.
- The target browser was started with `--user-data-dir=C:\chrome-wsl-automation`.
- The target browser was started with `--profile-directory=Default`.
- The desired sites were logged into inside that dedicated automation profile.

## Login State Protection

- Do not use temporary user-data-dir, incognito, guest, Playwright fresh profiles, bundled Chromium, or a WSL/Linux browser.
- Do not clear Cookie, LocalStorage, SessionStorage, profile preferences, site permissions, or extension state.
- Never clear login state for `work.weixin.qq.com`, `weixin.qq.com`, or `qq.com`.
- If WeCom/WeChat login expires, refresh the page or ask the user to scan again; do not delete or reset the profile.
- Close Chrome normally when possible; do not kill `chrome.exe` unless it is unresponsive.

## First-Line Checks

1. Print the Windows launcher if the automation browser is not already configured:

```bash
bash scripts/print_windows_automation_browser_launcher.sh
```

2. Run the built-in status check:

```bash
bash scripts/attach_windows_logged_in_chrome.sh --status
```

For machine-readable diagnostics:

```bash
bash scripts/attach_windows_logged_in_chrome.sh --status --json
```

3. Run readiness health. This should exit 0 when a usable websocket endpoint exists, even if gateway, relay, or process-flag diagnostics are warnings:

```bash
bash scripts/health_check.sh
```

Use strict health only when fixing the browser environment itself:

```bash
bash scripts/health_check.sh --strict
```

4. Probe the default localhost path from WSL:

```bash
curl http://127.0.0.1:9222/json/version
```

5. If that fails, probe the Windows host IP from WSL:

```bash
GW="$(ip -4 route show default | awk '$1 == "default" && $3 != "" { if (gateway == "") gateway = $3 } END { print gateway }')"
curl "http://$GW:9222/json/version"
```

If one of those returns JSON, the CDP HTTP endpoint is reachable and the helper should be able to derive the websocket endpoint.
Avoid `ip route | awk '... exit'` in scripts that run with `set -o pipefail`; early `awk` exit can close the pipe while `ip` is still writing, producing exit code 141.

6. List current tabs before reopening an authenticated URL:

```bash
curl "http://127.0.0.1:9222/json/list"
```

For SPA enterprise pages, use the existing tab's websocket/page state when possible. Reopening the same URL can lose transient hash parameters, form dirty state, or logged-in navigation context.

## Manual Recovery Flow

1. Print the websocket endpoint directly:

```bash
bash scripts/print_windows_chrome_ws_endpoint.sh
```

2. If direct access still fails, start the relay:

```bash
bash scripts/start_windows_chrome_cdp_relay.sh
```

3. Retry the websocket helper after the relay starts:

```bash
bash scripts/print_windows_chrome_ws_endpoint.sh
```

4. Try the readiness check, then the attach helper:

```bash
bash scripts/health_check.sh
bash scripts/attach_windows_logged_in_chrome.sh --session auth
```

5. Stop the relay when it is no longer needed:

```bash
bash scripts/stop_windows_chrome_cdp_relay.sh
```

## Secondary Diagnostics

If the HTTP endpoint is not reachable but you need to confirm the Windows automation profile itself is running, inspect the dedicated profile's `DevToolsActivePort` file from Windows:

```powershell
Get-Content "C:\chrome-wsl-automation\DevToolsActivePort"
```

Expected shape:

- line 1: port, must be `9222` for normal agent automation
- line 2: browser websocket path such as `/devtools/browser/<id>`

This is a secondary diagnostic. The preferred attach path is still `http://127.0.0.1:<port>/json/version` or the WSL gateway host, not scraping the default browser profile.

## Why This Layout Is More Stable

- It avoids the default browser profile, which Chrome 136+ restricts for remote debugging.
- It avoids fighting with a browser you are actively using for normal work.
- It keeps login state in one dedicated automation profile instead of recreating sessions inside WSL.
- It keeps browser settings and logged-in enterprise app state under `C:\chrome-wsl-automation\Default`.
- It keeps rendering, window management, and GPU handling on Windows.

## Security Notes

- The relay binds to the WSL gateway host by default instead of `0.0.0.0`.
- Override the bind host only when needed:

```bash
WSL_WINDOWS_CHROME_RELAY_BIND_HOST=0.0.0.0 bash scripts/start_windows_chrome_cdp_relay.sh
```

- If a `playwright-cli` session with the same name already exists, the attach helper closes that session before attach to avoid stale-session collisions.
