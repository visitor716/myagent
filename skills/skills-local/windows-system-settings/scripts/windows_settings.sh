#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ps_script="$script_dir/windows_settings.ps1"

if command -v wslpath >/dev/null 2>&1; then
  ps_script_win="$(wslpath -w "$ps_script")"
else
  ps_script_win="$ps_script"
fi

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script_win" "$@"
