# Network Power Monitor

Records read-only Windows network, WLAN, power-plan, battery, proxy, and recent
system-event snapshots so the next disconnect or `0x9f` crash has pre-failure
evidence.

The monitor does not restart adapters, change DNS, change proxy settings, or
switch power plans.

## Logs

Default log directory:

```text
C:\Users\zhanxp\Desktop\network-power-monitor
```

Important files:

- `heartbeat.csv` - compact timeline for every interval.
- `latest.txt` - latest detailed snapshot.
- `events.log` - relevant WLAN, Netwtw, Kernel-Power, DNS, WER, and driver events.
- `snapshots\*.txt` - recent detailed snapshots, pruned by `-MaxSnapshots`.

## Run Once

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action collect-once
```

## Watch in Current Window

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action watch -IntervalSeconds 30
```

## Install Login Startup and Start Now

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action install-startup -IntervalSeconds 30
```

The script copies itself to:

```text
%LOCALAPPDATA%\MyAgent\NetworkPowerMonitor\network-power-monitor.ps1
```

and creates:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\MyAgent-NetworkPowerMonitor.cmd
```

## Status

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action status
```

## Stop or Uninstall

Stop the running monitor:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action stop
```

Remove the login startup launcher:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\network-power-monitor.ps1 -Action uninstall-startup
```
