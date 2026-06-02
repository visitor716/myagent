---
name: windows-system-settings
description: Safely inspect and adjust Windows system settings from WSL/Codex using built-in Windows tools. Use when the user asks to change Windows brightness, fix a grey/disabled brightness slider, inspect monitor/display state, change volume, mute state, display timeout, sleep timeout, power plan, time zone, monitor/display behavior, or says 系统设置, Windows 设置, 调亮度, 亮度灰色, 亮度滑块灰色, 降低亮度, 调音量, 静音, 电源设置, 睡眠时间, 屏幕关闭时间, or similar local machine setting requests.
---

# Windows System Settings

## Overview

Use this skill to change reversible Windows settings from a WSL Codex session. Prefer built-in Windows interfaces (`powershell.exe`, WMI/CIM, `powercfg.exe`, `tzutil.exe`) and verify the final state before reporting completion.

## Safety Rules

- For low-risk reversible settings such as brightness, volume, mute, monitor timeout, sleep timeout, and power scheme, act directly when the user gives a clear target.
- Report `before -> after` when a setting is changed.
- Do not install third-party utilities just to change a setting.
- Do not change registry keys, firewall rules, BitLocker, Windows Defender, UAC, user accounts, drivers, services, VPN, proxy, startup apps, or security policy unless the user explicitly asks for that specific change and the workflow creates a backup or clear rollback path.
- Do not disable display adapters, virtual display drivers, or remote-control software unless the user explicitly approves that driver-level step.
- If the request is really proxy/VPN/Clash/aTrust related, use `clash-proxy` instead.
- If WMI says no brightness-capable monitor exists, do not guess. External monitors often need DDC/CI tools that may not be installed.

## Helper Script

Prefer the bundled helper for supported settings:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action get-brightness
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action set-brightness -Value 60
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action adjust-brightness -Delta -10
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action get-display-state
```

Supported actions:

- `get-brightness`
- `set-brightness -Value <0-100>`
- `adjust-brightness -Delta <signed integer>`
- `get-display-state`
- `set-internal-display`
- `refresh-brightness-ui`
- `get-volume`
- `set-volume -Value <0-100>`
- `adjust-volume -Delta <signed integer>`
- `mute`
- `unmute`
- `get-power`
- `set-display-timeout -Value <minutes> [-Power ac|dc|both]`
- `set-sleep-timeout -Value <minutes> [-Power ac|dc|both]`
- `set-power-scheme -Scheme balanced|power-saver|high-performance`

Use `Value 0` for timeout actions when the user explicitly asks for "never".

## Workflow

1. Identify the target setting and exact value:
   - "降低 10%" usually means subtract 10 percentage points from current brightness or volume.
   - "调到 60%" means set the target to exactly 60.
   - If the unit is ambiguous for timeout settings, assume minutes and say so.
2. Read current state first when the helper supports it.
3. Apply the setting.
4. Read back the setting or command output.
5. Summarize the setting changed and the final value.

## Grey Brightness Slider Workflow

Use this when Windows Quick Settings or Settings shows the brightness slider as grey/disabled.

1. Confirm the backend first:
   - Run `get-brightness`.
   - If WMI reports a brightness-capable monitor, test a small reversible change and restore the user's current value.
   - If WMI has no brightness-capable monitor, stop and report that Windows is not exposing a controllable internal panel.
2. Check the display/UI layer:
   - Run `get-display-state`.
   - Look for virtual display adapters such as Oray/Sunlogin, GameViewer, ToDesk, AnyDesk, RustDesk, or RDP-related display devices.
   - Confirm whether the session is `console` or a remote session.
3. Try reversible UI/display refresh steps:
   - Run `set-internal-display` to switch Windows to "PC screen only".
   - Run `refresh-brightness-ui` to restart Explorer and Windows shell UI surfaces.
   - Read brightness back afterward; do not assume the visible slider state changed unless the user or a screenshot confirms it.
4. If the slider is still grey:
   - Report the likely virtual display/driver interference.
   - Ask before disabling display adapters or remote-control software.
   - Prefer a temporary disable with a clear re-enable command over permanent uninstall or registry edits.

## Direct Windows Commands

Use these when the helper does not cover the request.

Brightness via WMI/CIM:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | Select-Object InstanceName,CurrentBrightness'
```

Display state and brightness UI refresh:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action get-display-state
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action set-internal-display
bash /home/zhanxp/projects/myagent/skills/skills-local/windows-system-settings/scripts/windows_settings.sh -Action refresh-brightness-ui
```

Display and sleep timeout:

```bash
powercfg.exe -change -monitor-timeout-ac 10
powercfg.exe -change -standby-timeout-ac 30
powercfg.exe /getactivescheme
```

Time zone:

```bash
tzutil.exe /g
tzutil.exe /s "China Standard Time"
```

Only set time zone when the user names the desired zone or locale clearly.

## Failure Handling

- If `powershell.exe` is missing or blocked, report the command failure and do not fall back to Linux-only settings.
- If a command requires Administrator rights, report that admin rights are required and stop unless there is a non-admin equivalent.
- If multiple monitors report brightness, apply the same clear target to each WMI brightness-capable monitor and list each `InstanceName: before -> after`.
- If the current value cannot be read after applying, report the command output and the verification gap.
- If WMI brightness works but the UI slider stays grey, treat it as display topology, shell UI, remote session, or virtual display driver interference; do not keep reapplying brightness values.
