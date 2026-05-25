---
name: wsl-windows-chrome
description: Attach from WSL to the dedicated Windows Chrome agent browser at C:\chrome-wsl-automation with fixed CDP port 9222 and profile Default. Use this skill first whenever an agent needs browser automation, preserved login state, Windows Chrome CDP, authenticated pages, or logged-in enterprise websites; never use temporary/incognito/guest profiles or clear cookies/storage.
---

# WSL Windows Chrome

## 全局路由偏好

以后任何项目中，只要任务需要 agent 连接 Windows Chrome、复用 Windows 侧登录态、操作已登录网页，或从 WSL 自动化浏览器，优先使用 `wsl-windows-chrome`。不要先开 WSL/Linux 内的新浏览器来试。

## Agent 专用浏览器状态合约

所有浏览器自动化必须复用同一个 Windows Chrome 持久 profile：

- `--remote-debugging-port=9222`
- `--user-data-dir=C:\chrome-wsl-automation`
- `--profile-directory=Default`

这个 profile 是 agent 专用登录态和浏览器设置的唯一保存位置。Cookie、LocalStorage、SessionStorage、扩展配置、站点权限、登录态、已打开页面状态都保存在 Windows 侧 profile 中；不要迁移到 WSL，不要提交到仓库，不要复制成临时 profile。

禁止事项：

- 禁止使用临时 `user-data-dir`、Playwright fresh profile、bundled Chromium、WSL/Linux 浏览器、incognito 或 guest 模式。
- 禁止清理 Cookie、LocalStorage、SessionStorage，禁止重置 profile。
- 禁止对 `work.weixin.qq.com`、`weixin.qq.com`、`qq.com` 清缓存、清登录态或删除站点数据。
- 企业微信提示登录超时时，只允许刷新页面或提示用户重新扫码；不允许删除 profile。
- 关闭浏览器时优先正常关闭窗口；不要直接强杀 `chrome.exe`，除非 Chrome 无响应。

连接优先级：

1. 优先连接现有 CDP：`http://127.0.0.1:9222/json/version`。
2. 如果 WSL 本地环回不可达，再探测 Windows 网关地址的 `9222`。
3. 只有固定 `9222` 不可达时才输出诊断和固定启动命令；不要自动切换到别的 CDP 端口。

可用性判定分两层：

- Readiness：`attach_windows_logged_in_chrome.sh --status --json` 返回 `ok=true`，或 `health_check.sh` 显示 `READY`，即可继续 attach。`gateway`、`relay`、Chrome 进程参数检查失败只作为 warning，不阻塞本机 WSL agent 使用 `127.0.0.1:9222`。
- Strict health：只有需要排查 Windows 防火墙、relay、profile 启动参数时才运行 `health_check.sh --strict`；严格模式下任何诊断失败都会返回非 0。

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

1. Start Windows Chrome, not a WSL/Linux browser.
2. Use fixed CDP port `9222`.
3. Use `--user-data-dir=C:\chrome-wsl-automation`.
4. Use `--profile-directory=Default`.
5. Let WSL attach over CDP; do not try to reuse the default day-to-day profile.

Run the attach helper first. It tries `127.0.0.1:9222`, then the WSL gateway host on `9222`. If the dedicated profile advertises a different active port in `DevToolsActivePort`, the helper reports that mismatch but does not switch ports. It then starts a relay to fixed `9222` only if direct access is unavailable. If all attempts fail, it exits with diagnostic information — it will NOT fall back to a fresh browser session.

## Default Workflow

1. Print the Windows launcher and start the dedicated Windows Chrome automation browser with `C:\chrome-wsl-automation`, profile `Default`, and port `9222`.
2. Log into Telegram, WeCom, WeChat, QQ, or other sites once inside that dedicated browser profile.
3. Run `scripts/attach_windows_logged_in_chrome.sh` from WSL when the task needs interactive browsing or browser automation.
4. Let the helper probe `127.0.0.1:9222` first, then the WSL gateway host on `9222`.
5. When `--url <target>` is supplied, the helper lists existing CDP page targets first. If the target page is already open, it activates that tab and skips navigation so page state is preserved.
6. Let the helper start relay-assisted attach only if direct access to fixed `9222` is unavailable.
7. If a `playwright-cli` session with the same name is already active, let the helper close that session before attach so stale-session collisions do not produce false success.
8. If attach still fails, the helper will exit with an error and diagnostic information — it will NOT fall back to a fresh browser session.

## Quick Start

```bash
# Print a Windows launcher for the dedicated automation browser
bash scripts/print_windows_automation_browser_launcher.sh > /tmp/start-windows-chrome-automation.bat

# Attach from WSL to the dedicated automation browser
bash scripts/attach_windows_logged_in_chrome.sh --url https://example.com

# Reuse an already-open matching target page before navigating; bind to a named session
bash scripts/attach_windows_logged_in_chrome.sh --session docs --url https://example.com

# Check whether the Windows automation browser is exposing CDP before attach
bash scripts/attach_windows_logged_in_chrome.sh --status

# Emit machine-readable status for other agents or scripts
bash scripts/attach_windows_logged_in_chrome.sh --status --json

# Readiness check; exits 0 when a usable websocket endpoint exists
bash scripts/health_check.sh

# Stable browser-control smoke test without playwright-cli
bash scripts/raw_cdp_smoke_test.sh

# Strict environment diagnostics; exits non-zero on gateway/relay/profile warnings
bash scripts/health_check.sh --strict

# (Default behavior) Require reuse of the dedicated Windows browser; do not open a fresh browser
bash scripts/attach_windows_logged_in_chrome.sh --session auth

# Print the raw CDP websocket endpoint for tools that connect directly
bash scripts/print_windows_chrome_ws_endpoint.sh

# Stop the relay after finishing work
bash scripts/stop_windows_chrome_cdp_relay.sh
```

## Operating Notes

- Keep `playwright-cli` as the control surface after attach. Use `playwright-cli -s=<session> snapshot`, `click`, `fill`, `goto`, and related commands normally.
- When a target URL is known, pass it through `--url`. The attach helper checks `/json/list` before attach; if a matching tab already exists, it activates that tab and does not run `playwright-cli goto`.
- Target reuse matches exact URL without fragment first. If the requested URL has no query string, it may also reuse an already-open page with the same scheme, host, and path, preserving query or hash state created by the site.
- Use `--no-reuse-existing-target` only when the task explicitly needs a fresh navigation instead of the already-open page state.
- If `playwright-cli attach` is unnecessary or unstable, use raw CDP first: probe `http://127.0.0.1:<port>/json/version`, list tabs with `/json/list`, select the target page websocket, then attach through the browser websocket or inspect current tabs before navigating.
- For stability validation, prefer `scripts/raw_cdp_smoke_test.sh`. It creates, lists, activates, and closes one temporary tab through Chrome DevTools HTTP without using `playwright-cli`.
- Do not run multiple `playwright-cli attach` attempts for the same session in parallel. If an attach or `snapshot` command stalls, close that session or use raw CDP instead of starting more background attaches.
- Wrap manual `playwright-cli` commands with `timeout` during diagnostics. A hung `playwright-cli` command is a control-layer failure, not proof that Windows Chrome CDP is unavailable.
- For logged-in enterprise apps, prefer focusing the existing tab over reopening the URL. Use `playwright-cli -s=<session> tab-list` and `tab-select <index>` so the active request/page state is preserved.
- Read [references/windows-chrome-cdp.md](references/windows-chrome-cdp.md) when attach fails and the troubleshooting or manual CDP flow is needed.
- Use `scripts/print_windows_chrome_ws_endpoint.sh` when a tool needs the raw websocket endpoint instead of a high-level `playwright-cli attach` flow.
- Assume the Windows automation browser is already running and logged in. This skill does not migrate cookies or profiles into WSL.
- There is NO fallback to fresh browser sessions. If CDP endpoint is not reachable, the helper will fail immediately with diagnostic information and setup instructions.
- `powershell.exe` is discovered from PATH first, then from standard `/mnt/c/Windows/...` locations so `[interop] appendWindowsPath=false` does not block attach.
- WSL gateway detection must avoid `ip route | awk '... exit'` under `set -o pipefail`; early `awk` exit can make `ip` return SIGPIPE/141 and abort otherwise healthy status checks.
- Relay-assisted attach uses a Windows PowerShell TCP relay and does not require Windows Node.js.
- The default `playwright-cli` session name is `wsl-windows-chrome`, not the generic `default`, to reduce collisions with unrelated browser work.
- Relay binding defaults to the WSL gateway host instead of `0.0.0.0`. Override with `WSL_WINDOWS_CHROME_RELAY_BIND_HOST` only when you intentionally need a different bind address.
- Default to Windows Chrome. Do not switch to Edge for normal user browser automation; use Edge only for a task that explicitly requires Edge and still keep a persistent non-temporary profile.
- Do not override the Windows automation profile root for normal work. The canonical agent profile is `C:\chrome-wsl-automation`.
- Do not override the preferred CDP port for normal work. The canonical agent port is `9222`.
- Use `--status --json` when another script, skill, or agent needs a stable machine-readable health snapshot before deciding whether to attach or start a relay.
- Use `health_check.sh` as a readiness check in normal agent tasks. A `READY with WARNINGS` result is usable and should not be reported as CDP unavailable.
- Use `health_check.sh --strict` only for environment diagnostics. Gateway, relay, or `--profile-directory=Default` warnings matter for hardening but should not block localhost CDP attach when `ready=true`.
- `--status --json` exposes `requested_cdp_port`, `resolved_cdp_port`, `discovered_cdp_port`, `active_port_path`, `local_cdp_ready`, `gateway_cdp_ready`, and `relay_cdp_ready`, plus the preferred endpoint chosen by the helper.
- Keep the same non-default `--user-data-dir` if login state should persist between runs.
- Do not point this skill at the default Chrome or Edge user data directory on Chrome 136+.
- The launcher helper uses fixed `9222`. If `9222` is occupied and does not answer `/json/version`, it fails with a conflict message rather than choosing another port.
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
- The helper name `attach_windows_logged_in_chrome.sh` is retained for compatibility, but the required target is the dedicated Windows Chrome automation browser, not the day-to-day browser.

## Resources

### scripts/

- `attach_windows_logged_in_chrome.sh`: Attach only to the dedicated Windows Chrome automation browser on fixed `9222`; fail immediately if CDP endpoint is not reachable.
- `health_check.sh`: Readiness check by default; use `--strict` for full gateway/relay/profile diagnostics.
- `raw_cdp_smoke_test.sh`: Deterministic raw CDP HTTP browser-control smoke test that does not use `playwright-cli`.
- `print_windows_automation_browser_launcher.sh`: Print a Windows `.bat` launcher that starts the dedicated automation browser with fixed `9222`, `C:\chrome-wsl-automation`, and profile `Default`.
- `print_windows_chrome_ws_endpoint.sh`: Print the direct or relay-backed websocket endpoint for raw CDP tools without switching to another profile port.
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
- `health_check.sh` 在 localhost CDP 可用时退出 0，即使 gateway、relay 或 profile 参数检查给出 warning
- `health_check.sh --strict` 在 gateway、relay 或 profile 参数检查失败时仍退出非 0
- 能 attach 到 Windows Chrome
- 不启动新的 Playwright 默认浏览器
- 使用 `C:\chrome-wsl-automation` 和 `Default` profile

### case-003: PowerShell 端口检测

期望：
- 不出现 Missing expression after ','
- 不出现 An expression was expected after '('
- $port 不会被 Bash 展开为空

### case-004: profile 记录了非 9222 端口

期望：
- 输出端口不匹配诊断
- 不自动切换到该端口
- 不启动临时浏览器
- 提示使用 `--remote-debugging-port=9222 --user-data-dir=C:\chrome-wsl-automation --profile-directory=Default` 重新启动

### case-005: 登录态保护

期望：
- 不删除 profile
- 不清理 Cookie、LocalStorage、SessionStorage
- 不对企业微信、微信、QQ 域名清登录状态
- 登录超时时只刷新或提示扫码

### case-006: 目标页复用

期望：
- `--url <target>` 先读取 `/json/list`
- 已打开目标页时激活该 tab
- 已打开目标页时不执行 `playwright-cli goto`
- 未找到目标页时保持原行为：attach 成功后再导航到目标 URL
