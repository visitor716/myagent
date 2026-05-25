#!/usr/bin/env bash
# Print a Windows launcher for a dedicated automation browser with CDP enabled.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"

usage() {
  cat <<'USAGE'
Usage: print_windows_automation_browser_launcher.sh [options]

Print a Windows .bat launcher that starts a dedicated automation browser.

Options:
  --browser <chrome|edge>  Select the Windows browser family
  --port <port>            Override the Windows CDP port (default: 9222; use 9222 unless explicitly required)
  --user-data-dir <path>   Override the Windows automation user-data-dir
  --help                   Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --browser)
      BROWSER="$2"
      shift 2
      ;;
    --port)
      CDP_PORT="$2"
      shift 2
      ;;
    --user-data-dir)
      WINDOWS_USER_DATA_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

BROWSER="$(wsl_windows_chrome_normalize_browser "$BROWSER")"
BROWSER_LABEL="$(wsl_windows_chrome_browser_label "$BROWSER")"
WINDOWS_USER_DATA_DIR_RESOLVED="$(wsl_windows_chrome_user_data_dir "$BROWSER" "$WINDOWS_USER_DATA_DIR")"

mapfile -t EXE_CANDIDATES < <(wsl_windows_chrome_windows_exe_candidates "$BROWSER")

cat <<EOF
:: Launch a dedicated $BROWSER_LABEL automation browser for WSL CDP attach.
@echo off
setlocal
set "PREFERRED_CDP_PORT=$CDP_PORT"
set "PROFILE_DIR=$WINDOWS_USER_DATA_DIR_RESOLVED"
set "PROFILE_DIRECTORY=Default"
set "BROWSER_EXE="
EOF

for candidate in "${EXE_CANDIDATES[@]}"; do
  printf 'if not defined BROWSER_EXE if exist "%s" set "BROWSER_EXE=%s"\n' "$candidate" "$candidate"
done

printf 'if not defined BROWSER_EXE (\n  echo %s executable not found.\n  exit /b 1\n)\n\n' "$BROWSER_LABEL"

cat <<'EOF'
for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "try { (Invoke-WebRequest -UseBasicParsing \"http://127.0.0.1:$env:PREFERRED_CDP_PORT/json/version\" -TimeoutSec 2) | Out-Null; Write-Output READY } catch { Write-Output NOT_READY }"') do set "CDP_READY=%%I"
if "%CDP_READY%"=="READY" (
  echo Existing dedicated automation browser CDP is reachable on 127.0.0.1:%PREFERRED_CDP_PORT%.
  exit /b 0
)

for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$port = [int]$env:PREFERRED_CDP_PORT; try { $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port); $listener.Start(); $listener.Stop(); Write-Output FREE } catch { Write-Output BUSY }"') do set "CDP_PORT_STATE=%%I"
if not "%CDP_PORT_STATE%"=="FREE" (
  echo CDP port %PREFERRED_CDP_PORT% is occupied but does not answer /json/version.
  echo Close the conflicting process or restart the dedicated automation browser with the fixed agent profile.
  exit /b 1
)

echo Using fixed CDP port %PREFERRED_CDP_PORT%
echo Using persistent agent profile %PROFILE_DIR% / %PROFILE_DIRECTORY%
start "" "%BROWSER_EXE%" ^
  --remote-debugging-port=%PREFERRED_CDP_PORT% ^
  --remote-debugging-address=0.0.0.0 ^
  --user-data-dir="%PROFILE_DIR%" ^
  --profile-directory="%PROFILE_DIRECTORY%"
EOF
