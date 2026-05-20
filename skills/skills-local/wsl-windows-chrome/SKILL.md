---
name: wsl-windows-chrome
description: Attach from WSL to a dedicated Windows Chrome or Edge automation browser that exposes a fixed CDP port with a non-default user-data-dir. Use when Codex needs authenticated browser state without reusing the day-to-day Windows browser profile.
---

# WSL Windows Chrome

## 强制规则：禁止 fallback 浏览器

当连接 Windows Chrome 的 Skill 连接不上 Windows 侧 Chrome CDP 时，禁止在 WSL 里启动或使用 Playwright 自带浏览器、fresh playwright-cli browser、bundled chromium 或任何 fallback browser。

原因：
这些浏览器不会复用 Windows Chrome 的登录状态，对 Telegram Web、BotFather、已登录网页、账号态自动化无效。

正确行为：
Windows Chrome CDP 不可达时，必须立即停止，退出码非 0，并输出：
- 当前检测端口
- 当前尝试连接地址
- 失败原因
- Windows 侧 Chrome 启动命令
- CDP 验证命令

## 强制规则：PowerShell 调用

在 WSL/Bash 中调用 Windows PowerShell 时：
- 如果 PowerShell 代码中包含 $变量，禁止用 Bash 双引号直接包裹 -Command
- 推荐写入临时 .ps1 文件后用 powershell.exe -File 执行
- 如果必须使用 -Command，外层必须使用 Bash 单引号，或者转义所有 PowerShell $ 变量
- 不允许出现 powershell.exe -Command "$port = ..." 这类写法

## Overview

Prefer a dedicated Windows automation browser when working from WSL on browser tasks. The stable setup is:

1. Start Chrome or Edge on Windows, not inside WSL
2. Prefer a fixed CDP port such as `9222`
3. Use a non-default `--user-data-dir` such as `C:\chrome-wsl-automation`
4. Let WSL attach over CDP; do not try to reuse the default day-to-day profile

Run the attach helper first. It tries `127.0.0.1:<port>`, then the WSL gateway host. If the requested port is unavailable but the dedicated profile advertises a different active port in `DevToolsActivePort`, the helper automatically switches to that port. It then starts a relay bound to the gateway host if direct access is still unavailable. If all attempts fail, it exits with an error and diagnostic information — it will NOT fall back to a fresh browser session.

## Default Workflow

1. Print the Windows launcher and start the dedicated automation browser with a non-default profile.
2. Log into Telegram, WeCom, or other sites once inside that dedicated browser profile.
3. Run `scripts/attach_windows_logged_in_chrome.sh` from WSL when the task needs interactive browsing or browser automation.
4. Let the helper probe `127.0.0.1:<port>` first, then the WSL gateway host. If the requested port conflicts with another browser instance, let it fall back to the active port recorded in the dedicated profile.
5. Let the helper start relay-assisted attach only if direct access is unavailable.
6. If a `playwright-cli` session with the same name is already active, let the helper close that session before attach so stale-session collisions do not produce false success.
7. If attach still fails, the helper will exit with an error and diagnostic information — it will NOT fall back to a fresh browser session.

## Quick Start

```bash
# Print a Windows launcher for the dedicated automation browser
bash scripts/print_windows_automation_browser_launcher.sh > /tmp/start-windows-chrome-automation.bat

# Attach from WSL to the dedicated automation browser
bash scripts/attach_windows_logged_in_chrome.sh --url https://example.com

# Bind the browser to a named playwright-cli session
bash scripts/attach_windows_logged_in_chrome.sh --session docs --url https://example.com

# Check whether the Windows automation browser is exposing CDP before attach
bash scripts/attach_windows_logged_in_chrome.sh --status

# Emit machine-readable status for other agents or scripts
bash scripts/attach_windows_logged_in_chrome.sh --status --json

# Override the CDP port or the dedicated Windows profile path
bash scripts/attach_windows_logged_in_chrome.sh --port 9333 --user-data-dir 'C:\chrome-wsl-automation'

# Use Microsoft Edge instead of Chrome with a separate automation profile
bash scripts/attach_windows_logged_in_chrome.sh --browser edge --session edge-auth --user-data-dir 'C:\edge-wsl-automation'

# (Default behavior) Require reuse of the dedicated Windows browser; do not open a fresh browser
bash scripts/attach_windows_logged_in_chrome.sh --session auth

# Print the raw CDP websocket endpoint for tools that connect directly
bash scripts/print_windows_chrome_ws_endpoint.sh

# Stop the relay after finishing work
bash scripts/stop_windows_chrome_cdp_relay.sh
```

## Operating Notes

- Keep `playwright-cli` as the control surface after attach. Use `playwright-cli -s=<session> snapshot`, `click`, `fill`, `goto`, and related commands normally.
- Read [references/windows-chrome-cdp.md](references/windows-chrome-cdp.md) when attach fails and the troubleshooting or manual CDP flow is needed.
- Use `scripts/print_windows_chrome_ws_endpoint.sh` when a tool needs the raw websocket endpoint instead of a high-level `playwright-cli attach` flow.
- Assume the Windows automation browser is already running and logged in. This skill does not migrate cookies or profiles into WSL.
- There is NO fallback to fresh browser sessions. If CDP endpoint is not reachable, the helper will fail immediately with diagnostic information and setup instructions.
- `powershell.exe` is discovered from PATH first, then from standard `/mnt/c/Windows/...` locations so `[interop] appendWindowsPath=false` does not block attach.
- Relay-assisted attach uses a Windows PowerShell TCP relay and does not require Windows Node.js.
- The default `playwright-cli` session name is `wsl-windows-chrome`, not the generic `default`, to reduce collisions with unrelated browser work.
- Relay binding defaults to the WSL gateway host instead of `0.0.0.0`. Override with `WSL_WINDOWS_CHROME_RELAY_BIND_HOST` only when you intentionally need a different bind address.
- Override browser detection with `--browser edge` or `WSL_WINDOWS_CHROME_BROWSER=edge`.
- Override the Windows automation profile root with `--user-data-dir` or `WSL_WINDOWS_CHROME_USER_DATA_DIR` when the browser profile lives outside the default dedicated path.
- Override the preferred CDP port with `--port` or `WSL_WINDOWS_CHROME_CDP_PORT`.
- Use `--status --json` when another script, skill, or agent needs a stable machine-readable health snapshot before deciding whether to attach, start a relay, or fall back.
- `--status --json` exposes `requested_cdp_port`, `resolved_cdp_port`, `discovered_cdp_port`, `active_port_path`, `local_cdp_ready`, `gateway_cdp_ready`, and `relay_cdp_ready`, plus the preferred endpoint chosen by the helper.
- Keep the same non-default `--user-data-dir` if login state should persist between runs.
- Do not point this skill at the default Chrome or Edge user data directory on Chrome 136+.
- The launcher helper now prefers `9222`, but automatically chooses another free port when `9222` is already occupied. The attach helper then discovers the actual active port from the dedicated profile when needed.
- Status field meaning:
  - `active_port_path`: either the `DevToolsActivePort` file path or `process:<pid>` when the helper had to fall back to process inspection
  - `local_cdp_ready`: `127.0.0.1:<port>` answers `/json/version` from WSL
  - `gateway_cdp_ready`: `<windows-gateway>:<port>` answers `/json/version` from WSL
  - `relay_cdp_ready`: relay endpoint answers `/json/version` from WSL
  - `preferred_mode`: the endpoint order currently selected for attach
- For enterprise WeChat / WPS-style live tables, prefer:
  1. `--session <name>` to bind a stable session
  2. `playwright-cli -s=<name> tab-list` and `tab-select` to focus the workbook page
  3. domain-specific tooling to inspect the live page after attach instead of reopening the URL in a fresh browser
- The helper name `attach_windows_logged_in_chrome.sh` is retained for compatibility, but the recommended target is now a dedicated automation browser, not the day-to-day browser.

## Resources

### scripts/

- `attach_windows_logged_in_chrome.sh`: Attach only to dedicated Windows automation browser; fail immediately if CDP endpoint is not reachable.
- `print_windows_automation_browser_launcher.sh`: Print a Windows `.bat` launcher that starts the dedicated automation browser with a preferred CDP port, automatically choosing another free port if needed.
- `print_windows_chrome_ws_endpoint.sh`: Print the direct or relay-backed websocket endpoint for raw CDP tools.
- `start_windows_chrome_cdp_relay.sh`: Expose the Windows automation browser CDP port to WSL when direct host access is blocked.
- `stop_windows_chrome_cdp_relay.sh`: Stop relay processes created by this skill.

### references/

- `windows-chrome-cdp.md`: Troubleshooting and manual CDP flow for the dedicated Windows automation browser from WSL.

## 验收测试说明

### case-001: 9222 未启动

期望：
- 输出 CDP 不可达
- 输出 Windows Chrome 启动命令
- 退出码非 0
- 不启动 Playwright 自带浏览器
- 不输出 Falling back to fresh playwright-cli browser

### case-002: 9222 已启动

期望：
- 能读取 /json/version
- 能拿到 webSocketDebuggerUrl
- 能 attach 到 Windows Chrome
- 不启动新的 Playwright 默认浏览器

### case-003: PowerShell 端口检测

期望：
- 不出现 Missing expression after ','
- 不出现 An expression was expected after '('
- $port 不会被 Bash 展开为空
