#!/usr/bin/env bash
set -euo pipefail

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "powershell.exe not found; nothing to stop." >&2
  exit 1
fi

PS_SCRIPT=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$relayRoot = Join-Path $env:USERPROFILE '.codex\wsl-windows-chrome'
$processes = Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match '^node(.exe)?$' -and $_.CommandLine -like ('*' + $relayRoot + '*') }
$count = @($processes).Count
foreach ($process in $processes) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}
Write-Output $count
PS1
)

STOPPED_COUNT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$PS_SCRIPT" | tr -d '\r' | tail -n 1)
echo "Stopped ${STOPPED_COUNT:-0} Windows Chrome CDP relay process(es) managed under %USERPROFILE%\.codex\wsl-windows-chrome"
