# Windows Chrome CDP from WSL

Read this file when `scripts/attach_windows_logged_in_chrome.sh` cannot attach automatically and the task still needs the Windows-side automation browser.

## Goal

Attach from WSL to a dedicated Windows Chrome or Edge automation browser without logging in again inside a fresh Linux browser profile.

## Recommended Topology

Use a dedicated Windows browser instance:

- Start Chrome or Edge on Windows
- Prefer a fixed CDP port such as `9222`
- Use a non-default `--user-data-dir` such as `C:\chrome-wsl-automation`
- Keep reusing that same profile so cookies and login state persist

Avoid pointing automation at the default day-to-day browser profile.
If the preferred port is already occupied, let the launcher choose another free port and let the WSL attach helper discover that active port from `DevToolsActivePort`.
If `DevToolsActivePort` is missing, the helper can now fall back to the browser process command line for the dedicated profile and reuse its `--remote-debugging-port`.

## Expected Windows-side State

- Chrome or Edge is already running on Windows.
- Remote debugging is enabled on the target browser.
- The target browser was started with a non-default `--user-data-dir`.
- The desired sites were logged into inside that dedicated automation profile.

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

3. Probe the default localhost path from WSL:

```bash
curl http://127.0.0.1:9222/json/version
```

4. If that fails, probe the Windows host IP from WSL:

```bash
GW="$(ip -4 route show default | awk '$1 == "default" && $3 != "" { if (gateway == "") gateway = $3 } END { print gateway }')"
curl "http://$GW:9222/json/version"
```

If one of those returns JSON, the CDP HTTP endpoint is reachable and the helper should be able to derive the websocket endpoint.
Avoid `ip route | awk '... exit'` in scripts that run with `set -o pipefail`; early `awk` exit can close the pipe while `ip` is still writing, producing exit code 141.

5. List current tabs before reopening an authenticated URL:

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

4. Try the attach helper in strict mode:

```bash
bash scripts/attach_windows_logged_in_chrome.sh --attach-only --session auth
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

- line 1: port, usually `9222`
- line 2: browser websocket path such as `/devtools/browser/<id>`

This is a secondary diagnostic. The preferred attach path is still `http://127.0.0.1:<port>/json/version` or the WSL gateway host, not scraping the default browser profile.

## Why This Layout Is More Stable

- It avoids the default browser profile, which Chrome 136+ restricts for remote debugging.
- It avoids fighting with a browser you are actively using for normal work.
- It keeps login state in one dedicated automation profile instead of recreating sessions inside WSL.
- It keeps rendering, window management, and GPU handling on Windows.

## Security Notes

- The relay binds to the WSL gateway host by default instead of `0.0.0.0`.
- Override the bind host only when needed:

```bash
WSL_WINDOWS_CHROME_RELAY_BIND_HOST=0.0.0.0 bash scripts/start_windows_chrome_cdp_relay.sh
```

- If a `playwright-cli` session with the same name already exists, the attach helper closes that session before attach to avoid stale-session collisions.
