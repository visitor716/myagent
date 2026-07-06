# Scripts

This directory groups repo-managed helper scripts by function.

- `apps/codex/`: Codex heartbeat, launcher, and Chrome DevTools MCP helpers.
- `apps/task-scheduler/`: Windows scheduled-task helpers and samples.
- `apps/file-transfer/`: DR Laser data copy, upload, and daily statistics scripts.
- `apps/cc-connect/`: cc-connect hidden start/restart helpers.
- `apps/windows-shell/`: Windows Explorer, file association, and context-menu helpers.
  - `invoke-powershell-encoded.sh`: WSL helper that runs PowerShell scripts via `-EncodedCommand`, preferring PowerShell 7, to avoid Bash/PowerShell quoting collisions.
- `libs/`: shared Python helper modules.
- `bootstrap/`: scripts that install or scaffold a local script hub.
- `config/`: historical script-related configuration snapshots.
- `legacy/`: notes or scratch files kept for traceability.
