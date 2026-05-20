#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"
RELAY_PORT="${WSL_WINDOWS_CHROME_RELAY_PORT:-39222}"
VERBOSE=false
JSON_OUTPUT=false

usage() {
  cat <<'USAGE'
Usage: health_check.sh [options]

Health check for WSL-Windows-Chrome connectivity.

Options:
  --browser <chrome|edge>    Select the Windows browser family
  --port <port>              Override the Windows CDP port (default: 9222)
  --user-data-dir <path>     Override the Windows automation user-data-dir
  --relay-port <port>        Override the WSL-visible relay port (default: 39222)
  --json                     Output results as JSON
  --verbose                  Print extra diagnostics
  --help                     Show this help
USAGE
}

log() {
  wsl_windows_chrome_log "$@"
}

# Check result tracking
declare -A CHECK_RESULTS
declare -A CHECK_REASONS
declare -A CHECK_SUGGESTIONS
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Add a check result
add_check() {
  local name="$1"
  local passed="$2"
  local reason="$3"
  local suggestion="$4"

  CHECK_RESULTS["$name"]="$passed"
  CHECK_REASONS["$name"]="$reason"
  CHECK_SUGGESTIONS["$name"]="$suggestion"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ "$passed" == "true" ]]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi
}

# Print a check result
print_check() {
  local name="$1"
  local passed="${CHECK_RESULTS[$name]}"
  local reason="${CHECK_REASONS[$name]}"

  if [[ "$passed" == "true" ]]; then
    echo -e "  [\033[32mPASS\033[0m] $name"
  else
    echo -e "  [\033[31mFAIL\033[0m] $name"
    if [[ -n "$reason" ]]; then
      echo -e "         Reason: $reason"
    fi
    if [[ -n "${CHECK_SUGGESTIONS[$name]:-}" ]]; then
      echo -e "         Fix: ${CHECK_SUGGESTIONS[$name]}"
    fi
  fi
}

# Print all check results in human-readable format
print_results() {
  echo "=== WSL Windows Chrome Health Check ==="
  echo ""
  echo "Browser: $BROWSER_LABEL"
  echo "CDP Port: $REQUESTED_CDP_PORT"
  echo "Windows Gateway: $WINDOWS_GATEWAY"
  echo ""
  echo "Checks:"
  for name in "${!CHECK_RESULTS[@]}"; do
    print_check "$name"
  done
  echo ""
  echo "Summary: $PASSED_CHECKS/$TOTAL_CHECKS checks passed"
  if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]]; then
    echo -e "Overall: \033[32mHEALTHY\033[0m"
  else
    echo -e "Overall: \033[31mUNHEALTHY\033[0m"
  fi
}

# Print results as JSON
print_results_json() {
  local checks_json=""
  local first=true

  for name in "${!CHECK_RESULTS[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      checks_json="$checks_json,"
    fi

    local passed="${CHECK_RESULTS[$name]}"
    local reason="${CHECK_REASONS[$name]}"
    local suggestion="${CHECK_SUGGESTIONS[$name]:-}"

    checks_json="$checks_json"
    checks_json="$checks_json$(printf '{"name":"%s","passed":%s,"reason":"%s","suggestion":"%s"}' \
      "$name" \
      "$(if [[ "$passed" == "true" ]]; then echo "true"; else echo "false"; fi)" \
      "$(printf '%s' "$reason" | sed 's/"/\\"/g')" \
      "$(printf '%s' "$suggestion" | sed 's/"/\\"/g')")"
  done

  cat <<JSON
{
  "browser": "$BROWSER",
  "browser_label": "$BROWSER_LABEL",
  "cdp_port": $REQUESTED_CDP_PORT,
  "windows_gateway": "$WINDOWS_GATEWAY",
  "relay_port": $RELAY_PORT,
  "total_checks": $TOTAL_CHECKS,
  "passed_checks": $PASSED_CHECKS,
  "overall_healthy": $(if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]]; then echo "true"; else echo "false"; fi),
  "checks": [$checks_json]
}
JSON
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
    --relay-port)
      RELAY_PORT="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
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
REQUESTED_CDP_PORT="$CDP_PORT"
WINDOWS_GATEWAY="$(wsl_windows_chrome_gateway)"

# Check 1: Check if we have powershell.exe
if wsl_windows_chrome_has_powershell; then
  add_check "powershell_available" "true" "powershell.exe is available" ""
else
  add_check "powershell_available" "false" "powershell.exe not found" "Install PowerShell or ensure it's in PATH"
fi

# Check 2: Check Windows Chrome process with --remote-debugging-port
if wsl_windows_chrome_has_powershell; then
  # Check process via PowerShell
  escaped_browser="$(wsl_windows_chrome_escape_ps_single_quote "$BROWSER")"
  escaped_dir="$(wsl_windows_chrome_escape_ps_single_quote "$WINDOWS_USER_DATA_DIR_RESOLVED")"

  ps=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
$browser = '__BROWSER__'
$userDataDir = '__USER_DATA_DIR__'

$processPattern = switch ($browser) {
  'edge' { '^msedge(.exe)?$' }
  default { '^chrome(.exe)?$' }
}

$escapedUserDataDir = [regex]::Escape($userDataDir)

$processes = Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -match $processPattern -and
    $_.CommandLine -match '--remote-debugging-port=(\d+)'
  }

if ($processes) {
  $process = $processes | Select-Object -First 1
  $match = [regex]::Match($process.CommandLine, '--remote-debugging-port=(\d+)')
  if ($match.Success) {
    Write-Output "FOUND:$($match.Groups[1].Value):$($process.ProcessId)"
  } else {
    Write-Output "NO_PORT"
  }
} else {
  Write-Output "NOT_FOUND"
}
PS1
  )

  ps="${ps//__BROWSER__/$escaped_browser}"
  ps="${ps//__USER_DATA_DIR__/$escaped_dir}"

  tmp_ps1=$(mktemp /tmp/wsl_windows_chrome_health_XXXXXX.ps1)
  trap 'rm -f "$tmp_ps1"' EXIT
  echo "$ps" >"$tmp_ps1"
  process_result="$(wsl_windows_chrome_powershell -File "$(wslpath -w "$tmp_ps1")" 2>/dev/null || true)"
  process_result="$(echo "$process_result" | tr -d '\r')"
  rm -f "$tmp_ps1"

  if [[ "$process_result" == FOUND:* ]]; then
    found_port="$(echo "$process_result" | cut -d: -f2)"
    pid="$(echo "$process_result" | cut -d: -f3)"
    add_check "windows_chrome_process" "true" "Found $BROWSER_LABEL process (PID: $pid) with --remote-debugging-port=$found_port" ""
    CHROME_PROCESS_PORT="$found_port"
  elif [[ "$process_result" == "NO_PORT" ]]; then
    add_check "windows_chrome_process" "false" "$BROWSER_LABEL process found but no --remote-debugging-port flag" "Start Chrome with --remote-debugging-port=$REQUESTED_CDP_PORT"
    CHROME_PROCESS_PORT=""
  else
    add_check "windows_chrome_process" "false" "No $BROWSER_LABEL process with --remote-debugging-port found" "Start Chrome with --remote-debugging-port=$REQUESTED_CDP_PORT"
    CHROME_PROCESS_PORT=""
  fi
else
  add_check "windows_chrome_process" "false" "Cannot check process (powershell unavailable)" "Install PowerShell or ensure it's in PATH"
  CHROME_PROCESS_PORT=""
fi

# Check 3: Check Windows localhost port 9222 (from WSL via PowerShell)
if wsl_windows_chrome_has_powershell; then
  escaped_port="$(wsl_windows_chrome_escape_ps_single_quote "$REQUESTED_CDP_PORT")"
  ps=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
$port = [int]'__PORT__'
try {
  $tcp = New-Object System.Net.Sockets.TcpClient
  $tcp.Connect("127.0.0.1", $port)
  $tcp.Close()
  Write-Output "REACHABLE"
} catch {
  Write-Output "UNREACHABLE"
}
PS1
  )
  ps="${ps//__PORT__/$escaped_port}"
  tmp_ps1=$(mktemp /tmp/wsl_windows_chrome_health_XXXXXX.ps1)
  trap 'rm -f "$tmp_ps1"' EXIT
  echo "$ps" >"$tmp_ps1"
  win_local_result="$(wsl_windows_chrome_powershell -File "$(wslpath -w "$tmp_ps1")" 2>/dev/null || true)"
  win_local_result="$(echo "$win_local_result" | tr -d '\r')"
  rm -f "$tmp_ps1"

  if [[ "$win_local_result" == "REACHABLE" ]]; then
    add_check "windows_localhost_port" "true" "Windows localhost:$REQUESTED_CDP_PORT is reachable (Windows side)" ""
  else
    add_check "windows_localhost_port" "false" "Windows localhost:$REQUESTED_CDP_PORT is not reachable (Windows side)" "Ensure Chrome is running with --remote-debugging-port=$REQUESTED_CDP_PORT"
  fi
else
  add_check "windows_localhost_port" "false" "Cannot check Windows port (powershell unavailable)" "Install PowerShell or ensure it's in PATH"
fi

# Check 4: Check WSL can reach Windows gateway on CDP port
if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if wsl_windows_chrome_endpoint_reachable "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT"; then
    add_check "wsl_gateway_port" "true" "WSL can reach Windows gateway $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" ""
  else
    add_check "wsl_gateway_port" "false" "WSL cannot reach Windows gateway $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" "Check Windows firewall or start Chrome with --remote-debugging-address=0.0.0.0"
  fi
else
  add_check "wsl_gateway_port" "false" "Could not determine Windows gateway" "Check WSL network configuration"
fi

# Check 5: Check /json/version endpoint via gateway
if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if version_json="$(wsl_windows_chrome_http_json_version "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
    add_check "json_version_endpoint" "true" "Successfully retrieved /json/version from $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" ""
    if [[ "$VERBOSE" == "true" ]]; then
      log "Version JSON: $version_json"
    fi
  else
    add_check "json_version_endpoint" "false" "Failed to retrieve /json/version from $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" "Ensure CDP endpoint is responding correctly"
  fi
else
  add_check "json_version_endpoint" "false" "Could not determine Windows gateway" "Check WSL network configuration"
fi

# Check 6: Check /json/list endpoint via gateway
if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if list_json="$(wsl_windows_chrome_fetch_url "http://$WINDOWS_GATEWAY:$REQUESTED_CDP_PORT/json/list" 2>/dev/null)"; then
    add_check "json_list_endpoint" "true" "Successfully retrieved /json/list from $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" ""
    if [[ "$VERBOSE" == "true" ]]; then
      tab_count="$(echo "$list_json" | python3 -c 'import sys, json; data = json.load(sys.stdin); print(len(data))' 2>/dev/null || echo "unknown")"
      log "Open tabs/pages: $tab_count"
    fi
  else
    add_check "json_list_endpoint" "false" "Failed to retrieve /json/list from $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" "Ensure CDP endpoint is responding correctly"
  fi
else
  add_check "json_list_endpoint" "false" "Could not determine Windows gateway" "Check WSL network configuration"
fi

# Check 7: Check relay port (if available)
RELAY_BIND_HOST="$(wsl_windows_chrome_relay_bind_host "$WINDOWS_GATEWAY")"
relay_available="false"
if [[ -n "$RELAY_BIND_HOST" ]]; then
  if wsl_windows_chrome_endpoint_reachable "$RELAY_BIND_HOST" "$RELAY_PORT"; then
    add_check "relay_port" "true" "Relay port $RELAY_BIND_HOST:$RELAY_PORT is reachable" ""
    relay_available="true"
  else
    add_check "relay_port" "false" "Relay port $RELAY_BIND_HOST:$RELAY_PORT not reachable" "(Optional - only needed if direct attach fails)"
  fi
else
  add_check "relay_port" "false" "Could not determine relay bind host" "Check WSL network configuration"
fi

# Check 8: Check WebSocket endpoint via gateway OR relay
websocket_found="false"
if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
    add_check "websocket_endpoint" "true" "Successfully parsed WebSocket endpoint from /json/version" ""
    websocket_found="true"
    if [[ "$VERBOSE" == "true" ]]; then
      log "WebSocket endpoint: $ws_endpoint"
    fi
  elif [[ "$relay_available" == "true" ]] && ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
    add_check "websocket_endpoint" "true" "Successfully parsed WebSocket endpoint from relay /json/version" ""
    websocket_found="true"
    if [[ "$VERBOSE" == "true" ]]; then
      log "WebSocket endpoint (relay): $ws_endpoint"
    fi
  else
    add_check "websocket_endpoint" "false" "Failed to parse WebSocket endpoint from /json/version" "Check if /json/version contains a valid webSocketDebuggerUrl"
  fi
else
  add_check "websocket_endpoint" "false" "Could not determine Windows gateway" "Check WSL network configuration"
fi

# Output results
if [[ "$JSON_OUTPUT" == "true" ]]; then
  print_results_json
else
  print_results
fi

# Exit with success if either all checks passed OR the critical checks (powershell, browser process, windows localhost, and either direct/relay) are working
direct_available="false"
if [[ "${CHECK_RESULTS["wsl_gateway_port"]:-}" == "true" ]] && [[ "${CHECK_RESULTS["json_version_endpoint"]:-}" == "true" ]]; then
  direct_available="true"
fi

if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]] || \
   ([[ "${CHECK_RESULTS["powershell_available"]:-}" == "true" ]] && \
    [[ "${CHECK_RESULTS["windows_chrome_process"]:-}" == "true" ]] && \
    [[ "${CHECK_RESULTS["windows_localhost_port"]:-}" == "true" ]] && \
    { [[ "$direct_available" == "true" ]] || [[ "$relay_available" == "true" ]]; }); then
  exit 0
else
  exit 1
fi
