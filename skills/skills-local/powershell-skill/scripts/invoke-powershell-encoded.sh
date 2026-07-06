#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  invoke-powershell-encoded.sh [--file PATH]
  invoke-powershell-encoded.sh --help

Reads PowerShell code from stdin by default, prefixes a quiet progress setting,
converts it to UTF-16LE Base64, then invokes PowerShell with -EncodedCommand.
It prefers Windows PowerShell 7+ (`pwsh.exe`) and falls back to Windows
PowerShell 5.1 (`powershell.exe`) only when `pwsh.exe` is unavailable.

Examples:
  invoke-powershell-encoded.sh <<'PS'
  $path = 'C:\Program Files'
  [pscustomobject]@{ User = $env:USERNAME; Path = $path } | ConvertTo-Json
  PS

  invoke-powershell-encoded.sh --file ./script.ps1

Environment:
  POWERSHELL_EXE  Override the Windows PowerShell executable path.
EOF
}

find_powershell() {
  local candidate latest windows_user

  if [[ -n "${POWERSHELL_EXE:-}" ]]; then
    printf '%s\n' "$POWERSHELL_EXE"
    return 0
  fi

  if command -v pwsh.exe >/dev/null 2>&1; then
    command -v pwsh.exe
    return 0
  fi

  windows_user="${WINDOWS_USER:-${USER:-}}"
  latest="$(
    for candidate in \
      "/mnt/c/Users/${windows_user}/AppData/Local/Microsoft/PowerShell" \
      '/mnt/c/Program Files/PowerShell' \
      '/mnt/c/Program Files (x86)/PowerShell'
    do
      if [[ -d "$candidate" ]]; then
        find "$candidate" -type f -iname pwsh.exe -print 2>/dev/null
      fi
    done | sort -V | tail -n 1
  )"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
    return 0
  fi

  for candidate in \
    pwsh.exe \
    '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' \
    '/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe'
  do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

encode_script() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    { printf "%s\n" "\$ProgressPreference = 'SilentlyContinue'"; cat; } |
      iconv -f UTF-8 -t UTF-16LE |
      base64 -w 0
  else
    { printf "%s\n" "\$ProgressPreference = 'SilentlyContinue'"; cat; } |
      iconv -f UTF-8 -t UTF-16LE |
      base64 |
      tr -d '\n'
  fi
}

script_file=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      if [[ $# -lt 2 ]]; then
        echo 'Missing value for --file' >&2
        exit 2
      fi
      script_file="$2"
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

powershell_exe="$(find_powershell)" || {
  echo 'powershell.exe not found; this helper requires WSL Windows interop.' >&2
  exit 127
}

if [[ -n "$script_file" ]]; then
  if [[ ! -f "$script_file" ]]; then
    echo "PowerShell script file not found: $script_file" >&2
    exit 2
  fi
  encoded="$(encode_script <"$script_file")"
else
  encoded="$(encode_script)"
fi

exec "$powershell_exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$encoded"
