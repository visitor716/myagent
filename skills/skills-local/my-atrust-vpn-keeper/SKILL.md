---
name: my-atrust-vpn-keeper
description: Log in to, monitor, diagnose, recover, and optionally install a Windows startup watchdog for Sangfor aTrust VPN from WSL/Codex. Use when the user mentions aTrust, Sangfor VPN, 深信服 VPN, VPN login, VPN password login, VPN auto exit, VPN timeout, auto reconnect, 登录 aTrust, 自动登录, 自动退出, 自动恢复, 掉线重连, or wants a local script/skill to log in to or keep aTrust available after it exits.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-atrust-vpn-keeper` once near the start; if it fails, continue.

# aTrust VPN Keeper

## Overview

Use this skill to log in to Windows aTrust VPN and keep it available when it is already expected to be running. Prefer supported Windows surfaces: service status, process checks, launching/focusing the aTrust tray only for explicit `login` / `recover`, one-shot login assistance, and an optional startup watchdog.

The background `watch` action respects manual client exit by default. If the user exits or closes the aTrust client/tray, `watch` must not actively relaunch aTrust. Use explicit `login`, explicit `recover`, or the opt-in `-RestartClientOnExit` switch only when relaunching the client after exit is wanted.

When the background probe reports `LoggedIn`, the helper must not foreground, topmost, click, paste, or otherwise disturb the aTrust window. Foregrounding and DPI-click login input are allowed only after a background `WindowCapture` probe confirms `LoggedOut`.

Do not bypass corporate VPN policy. aTrust session duration is often controlled server-side; this skill does not edit private aTrust databases, cookies, session storage, signed TOML configs, or stored credentials.

## Helper Script

Run the PowerShell helper from WSL with `wslpath -w`:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action login
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action recover
```

Supported actions:

- `status`: read service/process/install/task state only.
- `login-state`: classify the UI as logged in, logged out, or unknown using fixed-position color probes. It defaults to background window capture, does not start/unminimize/foreground aTrust, and returns `Unknown` if no capturable existing window is available; add `-ForegroundProbe` only for manual fallback troubleshooting.
- `login`: start/recover aTrust only when a login attempt is actually needed. If background probing reports `LoggedIn`, it skips without foregrounding the window; if the UI is confirmed `LoggedOut`, it can foreground the window and assist a one-shot login.
- `recover`: start `aTrustService` if stopped, launch `aTrustTray.exe` if the tray is missing, and nudge the tray when the tunnel is absent.
- `watch`: loop silently in the background, respect manual aTrust client/tray exit by default, optionally probe UI login state, and auto-login with a saved DPAPI credential only after a confirmed `LoggedOut` UI while the client is still running. For each confirmed logout event it rechecks the state immediately before login input, may foreground the login window up to `-MaxReloginAttemptsPerLogout` times, default `3`, then locks further auto-login until `LoggedIn` or client exit clears the unresolved logout.
- `install-task`: copy the helper to `%LOCALAPPDATA%\MyAgent\aTrustVpnKeeper\`, write a short `watch.cmd` launcher, and create a Windows logon Scheduled Task that points at the launcher. If Windows denies task creation, fall back to a current-user Startup folder `.cmd`, then to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Each Windows login starts a fresh watchdog process, but an unresolved logout lockout persists until `LoggedIn` or client exit. Each aTrust logout event can trigger up to 3 foreground relogin attempts by default.
- `uninstall-task`: remove the watchdog task, Startup fallback, and HKCU Run fallback.
- `task-status`: show the watchdog task, Startup fallback, or HKCU Run fallback state.
- `save-credential`: save a username/password for unattended relogin using Windows DPAPI CurrentUser encryption.
- `clear-credential`: remove the saved aTrust credential.
- `credential-status`: show whether a saved credential exists without printing the password.

Useful options:

- `-IntervalSeconds <n>`: watch interval, default `60`, minimum `1`. Use `1` for near-immediate relogin after the background probe detects `LoggedOut`.
- `-ConsecutiveFailures <n>`: failures before recover, default `2`.
- `-MaxRecoveries <n>`: stop watch after this many recoveries, default `3`; use `0` for a persistent unattended VPN relogin watchdog.
- `-MaxChecks <n>`: stop watch after this many status checks, useful for bounded tests; `0` means unlimited.
- `-ReloginCooldownSeconds <n>`: after a failed auto-login attempt, wait this many seconds before trying again, default `60`. This keeps the watcher alive without stealing focus every 10 seconds if aTrust blocks simulated input.
- `-MaxReloginAttemptsPerLogout <n>`: maximum foreground auto-login attempts for one confirmed `LoggedOut` event, default `3`. The counter resets only after `LoggedIn` or client exit. After attempts are exhausted, the watcher writes a local `%LOCALAPPDATA%\MyAgent\aTrustVpnKeeper\logout-lockout.json` marker so watcher restarts do not immediately open another three-attempt round for the same unresolved logout. Ordinary `Unknown` probes do not start or reset this counter, and `Unknown` after a confirmed logout no longer consumes attempts because the watcher refuses to foreground or type without explicit `LoggedOut` evidence.
- `-UnknownLoginStateThreshold <n>`: when `login-state` is `Unknown` for this many consecutive checks, keep logging that the state is unresolved, default `3`. `Unknown` no longer triggers foreground login because it is not confirmed logout evidence.
- `-Username <name>`: optional username for one-shot UI login assistance.
- `-InputMethod DpiClick|ClipboardPaste|SendKeys`: login input method, default `DpiClick`. Use `DpiClick` for the current aTrust Electron login page because it requires DPI-aware coordinate clicks before clipboard paste.
- `-NoSubmit`: fill the visible login window but do not press Enter, useful for first-run calibration.
- `-PostLoginWaitSeconds <n>`: seconds to wait before checking tunnel health after login input, default `8`.
- `-PasswordFromStdin`: read one password line from stdin for one-shot UI login assistance; do not use command-line password arguments.
- `-PromptForPassword`: prompt interactively via PowerShell `Read-Host -AsSecureString`.
- `-AutoLogin`: use the saved DPAPI credential to run the login flow. For `login`, this does not trust process/tunnel health as proof of login state; it continues with the UI login attempt unless `-NoSubmit` is used.
- `-ProbeLoginState`: during `watch`, classify whether the UI is logged out even when service/process/tunnel health still looks normal. The watcher uses background window capture and should not steal focus. `install-task -AutoLogin` enables this automatically.
- `-RestartClientOnExit`: opt in to the old watchdog behavior that relaunches aTrust when the client/tray is absent. Do not use this when the user wants manual aTrust exit to stay respected.
- `-ForegroundProbe`: fallback probe mode for manual `login-state` troubleshooting that brings aTrust to the foreground and uses screen capture. `watch` and `install-task` ignore foreground probing so scheduled monitoring stays silent.
- `-DryRun`: print intended recovery or task actions without changing Windows state.
- `-ForceRestart`: explicitly restart aTrust tray processes before recovery.
- `-ForceLogin`: open the login flow even if aTrust currently appears healthy.

Known working local login path:

- aTrust currently behaves like an Electron/Chromium app whose login fields are not exposed through useful UIAutomation controls; UIAutomation may only see the top-level window.
- Prefer `-InputMethod DpiClick`. The helper calls `SetProcessDPIAware()`, moves the visible aTrust window to `(0,0)` at `1366x768`, clicks the physical username/password/login coordinates, pastes through the clipboard, then restores the clipboard.
- The UI logout detector samples the blue login button region and the green logged-in badge region. It is intentionally local and OCR-free. Normal monitoring uses `WindowCapture` against an already existing aTrust window handle and should not affect the active application; foreground screen capture is only the manual `-ForegroundProbe` fallback.
- Do not treat `Healthy=True`, `aTrustXtunnel.exe`, or service/process presence as proof that the user is still logged in. Long idle timeout can leave service/process/tunnel looking healthy while the visible aTrust UI is already back on the login page. For timeout/logout incidents, always check `login-state` or run `watch` with `-ProbeLoginState`.
- Current calibrated color-probe thresholds: login page is `LoggedOut` when the blue login button region ratio is greater than `0.25`, or when the wider window scan sees enough aTrust blue to catch the server-side logout notification/local password page; workbench is `LoggedIn` when the green account badge region ratio is greater than `0.03`. Known local samples were `loginBlue=0.716, loggedInGreen=0.000` when logged out, `loginBlueWide=0.019` on the logout notification window, and `loginBlue=0.000, loggedInGreen=0.108` when logged in.
- aTrust may expose the small logout notification as the only `MainWindowHandle`; the helper enumerates all aTrust top-level windows and prefers the largest main window for clicks, while allowing the small notification window only as logout evidence during background state probing.
- During timeout/logout transition, aTrust may show an intermediate confirmation modal. In that state background capture can report `Unknown` with both ratios at `0.000` for many checks, while service/tunnel still look healthy. The watcher stays silent on `Unknown`; it only foregrounds aTrust once after the background probe confirms `LoggedOut`. `Unknown` checks after a login attempt are logged but do not consume the remaining per-logout attempts.
- If the watcher has exhausted the per-logout attempts, later `Unknown -> LoggedOut` probe changes for the same unresolved logout do not start a fresh attempt round. A fresh round starts only after `LoggedIn` or client exit clears the local lockout marker.
- If a future manual coordinate test clicks the wrong window or misses the aTrust menu under Windows scaling, retry through the helper path or a PowerShell click helper that first calls `SetProcessDPIAware()`. Non-DPI-aware temporary click snippets can land on the wrong physical coordinates.
- Monitoring stays silent. Unattended relogin may still briefly foreground aTrust once per confirmed logout event because the current login form needs DPI clicks and clipboard paste. The helper records the previous foreground window before login input and attempts to restore it immediately after sending credentials.
- `Login-Atrust -WatchMode` rechecks background `login-state` immediately before foregrounding or clicking. If the state is `LoggedIn` or `Unknown`, it skips login input and leaves the active window alone.
- Manual client exit stays respected in `watch`: if aTrust tray/main window is gone, the watcher logs the state and does not call `recover` or start `aTrustTray.exe`. Use `-RestartClientOnExit` only when automatic relaunch after exit is explicitly desired.
- If auto-login throws or aTrust refuses foreground activation, the watcher must log `watch login attempt failed` and continue running. Do not let a single failed relogin kill the watchdog.
- When invoking the installed helper through `powershell.exe -Command` from Bash, wrap the PowerShell command in single quotes so Bash does not consume `$env:LOCALAPPDATA`:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '& "$env:LOCALAPPDATA\MyAgent\aTrustVpnKeeper\atrust_vpn_keeper.ps1" -Action login -Username "<username>" -AutoLogin -ForceLogin -InputMethod DpiClick -PostLoginWaitSeconds 12'
```

## Workflow

1. Start with login/status:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action login
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action status
```

2. To assist a one-shot password login without storing the password, pipe the password through stdin from a transient caller and include `-PasswordFromStdin`. Never put the password in the script, registry startup command, docs, logs, or git:

```bash
# Example shape only; do not save real passwords in shell history or files.
printf '%s\n' '<password>' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action login -Username '<username>' -PasswordFromStdin -ForceLogin
```

For first-run calibration, add `-NoSubmit`; it should fill the foreground aTrust login window without pressing Enter:

```bash
printf '%s\n' '<password>' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action login -Username '<username>' -PasswordFromStdin -ForceLogin -NoSubmit
```

If `DpiClick` is blocked by aTrust, retry with `-InputMethod ClipboardPaste` or `-InputMethod SendKeys`.

3. To enable unattended relogin after VPN drops, save the credential once, then install the watchdog with `-AutoLogin`. The password is encrypted with Windows DPAPI for the current Windows user; it is not written in plaintext, logs, task commands, or registry startup commands:

```bash
printf '%s\n' '<password>' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action save-credential -Username '<username>' -PasswordFromStdin
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action install-task -Username '<username>' -AutoLogin -InputMethod DpiClick -MaxRecoveries 3 -MaxReloginAttemptsPerLogout 3
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action credential-status
```

For near-immediate timeout/logout relogin, use a 1-second watcher and keep UI probing enabled:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action install-task -Username '<username>' -AutoLogin -ProbeLoginState -InputMethod DpiClick -IntervalSeconds 1 -PostLoginWaitSeconds 12 -ReloginCooldownSeconds 60 -MaxReloginAttemptsPerLogout 3 -UnknownLoginStateThreshold 3 -MaxRecoveries 0
powershell.exe -NoProfile -Command 'Start-Process -WindowStyle Hidden -FilePath "$env:LOCALAPPDATA\MyAgent\aTrustVpnKeeper\watch.cmd"'
```

Do not add `-ForegroundProbe` to the installed watcher; current `watch` ignores it and enforces background `WindowCapture`. The intended steady-state log line is `source=WindowCapture`.

4. If aTrust exited or the service/tray/tunnel is missing, run:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action recover
```

5. To install or refresh the automatic watchdog without saved-credential relogin:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action install-task
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action task-status
```

The installed startup mechanism runs at Windows logon with `-MaxRecoveries 3`. After 3 recovery attempts it stops recovering until the next login starts a new watchdog process.

6. To remove it:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action uninstall-task
```

## Timeout Logout Verification

Use this checklist when the user asks whether long-idle logout is monitored correctly:

1. Confirm the watcher is actually running with `-IntervalSeconds 1 -AutoLogin -ProbeLoginState -UnknownLoginStateThreshold 3 -MaxRecoveries 0`:

```bash
powershell.exe -NoProfile -Command 'Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "atrust_vpn_keeper.ps1" -and $_.CommandLine -match "Action watch" -and $_.ProcessId -ne $PID } | Select-Object ProcessId,Name,CommandLine | Format-List'
```

2. Confirm the UI login state directly. This is the source of truth for idle timeout logout and should report `CaptureSource : WindowCapture` in normal silent mode:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action login-state
```

3. Tail the log before and after a manual logout simulation:

```bash
powershell.exe -NoProfile -Command 'Get-Content "$env:LOCALAPPDATA\MyAgent\aTrustVpnKeeper\keeper.log" -Tail 40'
```

4. Simulate the service-side timeout by manually choosing aTrust UI `注销登录` from the logged-in workbench, then wait for the next 1-second probe. A passing run may show `login-state probe state=LoggedOut`; it should immediately log `logged-out UI detected; relogin attempt [1/3]`, `loaded saved aTrust credential`, possible confirmation clicks, `sent aTrust login input via DpiClick`, then `login-state probe state=LoggedIn`. If the first attempt leaves the window minimized or the probe turns `Unknown`, the watcher may continue attempts `[2/3]` and `[3/3]` only because the same logout event was already confirmed. After `[3/3]`, it should log `auto-login locked until LoggedIn after relogin attempts exhausted` and must not start another auto-login round for later `Unknown -> LoggedOut` transitions. If the probe is `Unknown` without a prior confirmed logout, the watcher stays silent and must not foreground the VPN window.

5. If `status` says healthy but `login-state` says `LoggedOut`, trust `login-state`; the monitor must relogin even though service/process/tunnel checks are green.

## Safety Rules

- Do not store VPN passwords, SMS codes, TOTP secrets, cookies, tokens, or full internal VPN URLs in this repo. When unattended relogin is explicitly requested, only use the helper's DPAPI CurrentUser credential file under `%LOCALAPPDATA%\MyAgent\aTrustVpnKeeper\credential.json`.
- Do not pass VPN passwords as command-line arguments because they can appear in process lists and shell history. Use `-PasswordFromStdin` or `-PromptForPassword` only for one-shot login assistance.
- Do not print, log, commit, or paste the saved credential blob as if it were harmless; it is encrypted for this Windows user but still sensitive local state.
- Do not modify aTrust signed config files or SQLite databases unless the user explicitly requests that risk and a backup/rollback plan exists.
- Treat `aTrustXtunnel.exe` absence as a sign that a saved-login reconnect may be needed. The helper can launch/focus the tray and paste one-shot credentials, but it cannot safely solve MFA or a service-side forced logout.
- Clipboard-based login temporarily replaces the Windows clipboard and then restores the previous clipboard object; if restoration fails, report that risk instead of retrying with stored secrets.
- Use `-DryRun` before installing tasks or force restarting aTrust when the user's active VPN session should not be interrupted.
- If recovery repeatedly opens the login UI but does not reconnect, report that the service-side session expired or MFA/manual login is required.
