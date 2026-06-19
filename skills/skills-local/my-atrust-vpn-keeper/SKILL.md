---
name: my-atrust-vpn-keeper
description: Monitor, diagnose, recover, and optionally install a Windows Scheduled Task watchdog for Sangfor aTrust VPN from WSL/Codex. Use when the user mentions aTrust, Sangfor VPN, 深信服 VPN, VPN auto exit, VPN timeout, auto reconnect, 自动退出, 自动登录, 自动恢复, 掉线重连, or wants a local script/skill to restart or keep aTrust available after it exits.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-atrust-vpn-keeper` once near the start; if it fails, continue.

# aTrust VPN Keeper

## Overview

Use this skill to keep Windows aTrust VPN available after the client exits, the tray disappears, the service stops, or tunnel processes vanish. Prefer recovery through supported Windows surfaces: service status, process checks, launching the aTrust tray, and an optional Scheduled Task watchdog.

Do not bypass corporate VPN policy. aTrust session duration is often controlled server-side; this skill does not edit private aTrust databases, cookies, session storage, signed TOML configs, or stored credentials.

## Helper Script

Run the PowerShell helper from WSL with `wslpath -w`:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action recover
```

Supported actions:

- `status`: read service/process/install/task state only.
- `recover`: start `aTrustService` if stopped, launch `aTrustTray.exe` if the tray is missing, and nudge the tray when the tunnel is absent.
- `watch`: loop and recover after consecutive unhealthy checks, defaulting to 3 recovery attempts per watchdog process.
- `install-task`: copy the helper to `%LOCALAPPDATA%\MyAgent\aTrustVpnKeeper\` and create a Windows logon Scheduled Task. If Windows denies task creation, fall back to a current-user Startup folder `.cmd`, then to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Each login starts a fresh watchdog, so the 3-attempt limit resets on the next login.
- `uninstall-task`: remove the watchdog task, Startup fallback, and HKCU Run fallback.
- `task-status`: show the watchdog task, Startup fallback, or HKCU Run fallback state.

Useful options:

- `-IntervalSeconds <n>`: watch interval, default `60`.
- `-ConsecutiveFailures <n>`: failures before recover, default `2`.
- `-MaxRecoveries <n>`: stop watch after this many recoveries, default `3`; `0` means unlimited only when explicitly requested.
- `-MaxChecks <n>`: stop watch after this many status checks, useful for bounded tests; `0` means unlimited.
- `-DryRun`: print intended recovery or task actions without changing Windows state.
- `-ForceRestart`: explicitly restart aTrust tray processes before recovery.

## Workflow

1. Start with status:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action status
```

2. If aTrust exited or the service/tray/tunnel is missing, run:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action recover
```

3. To install the automatic watchdog:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action install-task
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action task-status
```

The installed startup mechanism runs at Windows logon with `-MaxRecoveries 3`. After 3 recovery attempts it stops recovering until the next login starts a new watchdog process.

4. To remove it:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /home/zhanxp/projects/myagent/skills/skills-local/my-atrust-vpn-keeper/scripts/atrust_vpn_keeper.ps1)" -Action uninstall-task
```

## Safety Rules

- Do not store VPN passwords, SMS codes, TOTP secrets, cookies, tokens, or full internal VPN URLs in this repo.
- Do not modify aTrust signed config files or SQLite databases unless the user explicitly requests that risk and a backup/rollback plan exists.
- Treat `aTrustXtunnel.exe` absence as a sign that a saved-login reconnect may be needed. The helper can launch/focus the tray, but it cannot safely solve MFA or a service-side forced logout.
- Use `-DryRun` before installing tasks or force restarting aTrust when the user's active VPN session should not be interrupted.
- If recovery repeatedly opens the login UI but does not reconnect, report that the service-side session expired or MFA/manual login is required.
