#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

if ! wsl_windows_chrome_has_powershell; then
  echo "powershell.exe not found; nothing to stop." >&2
  exit 1
fi

tmp_ps1=$(mktemp /tmp/wsl_windows_chrome_XXXXXX.ps1)
trap 'rm -f "$tmp_ps1"' EXIT

cat >"$tmp_ps1" <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$relayRoot = Join-Path $env:USERPROFILE '.codex\wsl-windows-chrome'
$processes = Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match '^(node|powershell|pwsh)(.exe)?$' -and $_.CommandLine -like ('*' + $relayRoot + '*') }
$count = @($processes).Count
foreach ($process in $processes) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}
Write-Output $count
PS1

STOPPED_COUNT=$(wsl_windows_chrome_powershell -File "$(wslpath -w "$tmp_ps1")" | tr -d '\r' | tail -n 1)
rm -f "$tmp_ps1"
echo "Stopped ${STOPPED_COUNT:-0} Windows Chrome CDP relay process(es) managed under %USERPROFILE%\.codex\wsl-windows-chrome"
