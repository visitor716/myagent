#!/usr/bin/env bash
set -euo pipefail

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
$relayPath = Join-Path \$env:USERPROFILE 'chrome_cdp_proxy.js'
Get-CimInstance Win32_Process |
  Where-Object { \$_.Name -match 'node' -and \$_.CommandLine -like \"*\$relayPath*\" } |
  ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }
"

echo "Stopped Windows Chrome CDP relay processes matching %USERPROFILE%\\chrome_cdp_proxy.js"
