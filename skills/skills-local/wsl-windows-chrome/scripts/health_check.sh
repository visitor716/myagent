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
STRICT=false

usage() {
  cat <<'USAGE'
Usage: health_check.sh [options]

Health check for WSL-Windows-Chrome connectivity.

Options:
  --browser <chrome|edge>    Select the Windows browser family
  --port <port>              Override the Windows CDP port (default: 9222)
  --user-data-dir <path>     Override the Windows automation user-data-dir
  --relay-port <port>        Override the WSL-visible relay port (default: 39222)
  --strict                   Require every diagnostic check to pass
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
declare -A CHECK_SEVERITIES
TOTAL_CHECKS=0
PASSED_CHECKS=0
READINESS_READY=false
STRICT_HEALTHY=false
OVERALL_SUCCESS=false

# Add a check result
add_check() {
  local name="$1"
  local passed="$2"
  local reason="$3"
  local suggestion="$4"
  local severity="${5:-required}"

  CHECK_RESULTS["$name"]="$passed"
  CHECK_REASONS["$name"]="$reason"
  CHECK_SUGGESTIONS["$name"]="$suggestion"
  CHECK_SEVERITIES["$name"]="$severity"
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
  local severity="${CHECK_SEVERITIES[$name]:-required}"

  if [[ "$passed" == "true" ]]; then
    echo -e "  [\033[32mPASS\033[0m] $name"
  elif [[ "$STRICT" != "true" && "$severity" == "warning" ]]; then
    echo -e "  [\033[33mWARN\033[0m] $name"
    if [[ -n "$reason" ]]; then
      echo -e "         Reason: $reason"
    fi
    if [[ -n "${CHECK_SUGGESTIONS[$name]:-}" ]]; then
      echo -e "         Fix: ${CHECK_SUGGESTIONS[$name]}"
    fi
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
echo "User Data Dir: $WINDOWS_USER_DATA_DIR_RESOLVED"
echo "Profile Directory: Default"
echo "Windows Gateway: $WINDOWS_GATEWAY"
echo "Mode: $(if [[ "$STRICT" == "true" ]]; then echo "strict"; else echo "readiness"; fi)"
  echo ""
  echo "Checks:"
  for name in "${!CHECK_RESULTS[@]}"; do
    print_check "$name"
  done
  echo ""
  echo "Summary: $PASSED_CHECKS/$TOTAL_CHECKS checks passed"
  if [[ "$STRICT" == "true" && "$STRICT_HEALTHY" == "true" ]]; then
    echo -e "Overall: \033[32mHEALTHY\033[0m"
  elif [[ "$STRICT" == "true" ]]; then
    echo -e "Overall: \033[31mUNHEALTHY\033[0m"
  elif [[ "$READINESS_READY" == "true" && "$STRICT_HEALTHY" == "true" ]]; then
    echo -e "Overall: \033[32mREADY / HEALTHY\033[0m"
  elif [[ "$READINESS_READY" == "true" ]]; then
    echo -e "Overall: \033[33mREADY with WARNINGS\033[0m"
  else
    echo -e "Overall: \033[31mNOT READY\033[0m"
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
    local severity="${CHECK_SEVERITIES[$name]:-required}"

    checks_json="$checks_json"
    checks_json="$checks_json$(printf '{"name":"%s","passed":%s,"severity":"%s","reason":"%s","suggestion":"%s"}' \
      "$name" \
      "$(if [[ "$passed" == "true" ]]; then echo "true"; else echo "false"; fi)" \
      "$severity" \
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
  "mode": "$(if [[ "$STRICT" == "true" ]]; then echo "strict"; else echo "readiness"; fi)",
  "ready": $READINESS_READY,
  "strict_healthy": $STRICT_HEALTHY,
  "overall_success": $OVERALL_SUCCESS,
  "total_checks": $TOTAL_CHECKS,
  "passed_checks": $PASSED_CHECKS,
  "overall_healthy": $STRICT_HEALTHY,
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
    --strict)
      STRICT=true
      shift
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
  add_check "powershell_available" "true" "powershell.exe is available" "" "warning"
else
  add_check "powershell_available" "false" "powershell.exe not found" "Install PowerShell or ensure it's in PATH" "warning"
fi

# Check 2: Check Windows Chrome process with the fixed agent profile
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
    $_.CommandLine -match '--remote-debugging-port=(\d+)' -and
    $_.CommandLine -match $escapedUserDataDir
  }

if ($processes) {
  $process = $processes | Select-Object -First 1
  $match = [regex]::Match($process.CommandLine, '--remote-debugging-port=(\d+)')
  if ($match.Success) {
    $profileOk = [regex]::IsMatch($process.CommandLine, '--profile-directory="?Default"?')
    Write-Output "FOUND:$($match.Groups[1].Value):$($process.ProcessId):$profileOk"
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
    profile_ok="$(echo "$process_result" | cut -d: -f4)"
    if [[ "$found_port" != "$REQUESTED_CDP_PORT" ]]; then
      add_check "windows_chrome_process" "false" "Found agent profile process (PID: $pid) on port $found_port, expected $REQUESTED_CDP_PORT" "Relaunch with --remote-debugging-port=$REQUESTED_CDP_PORT" "warning"
    elif [[ "$profile_ok" != "True" ]]; then
      add_check "windows_chrome_process" "false" "Found agent profile process (PID: $pid) without --profile-directory=Default" "Relaunch with --profile-directory=Default" "warning"
    else
      add_check "windows_chrome_process" "true" "Found $BROWSER_LABEL agent profile process (PID: $pid) with fixed port $found_port and profile Default" "" "warning"
    fi
    CHROME_PROCESS_PORT="$found_port"
  elif [[ "$process_result" == "NO_PORT" ]]; then
    add_check "windows_chrome_process" "false" "$BROWSER_LABEL process found but no --remote-debugging-port flag" "Start Chrome with --remote-debugging-port=$REQUESTED_CDP_PORT" "warning"
    CHROME_PROCESS_PORT=""
  else
    add_check "windows_chrome_process" "false" "No $BROWSER_LABEL process using $WINDOWS_USER_DATA_DIR_RESOLVED with --remote-debugging-port found" "Start Chrome with --remote-debugging-port=$REQUESTED_CDP_PORT --user-data-dir=$WINDOWS_USER_DATA_DIR_RESOLVED --profile-directory=Default" "warning"
    CHROME_PROCESS_PORT=""
  fi
else
  add_check "windows_chrome_process" "false" "Cannot check process (powershell unavailable)" "Install PowerShell or ensure it's in PATH" "warning"
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
    add_check "windows_localhost_port" "true" "Windows localhost:$REQUESTED_CDP_PORT is reachable (Windows side)" "" "warning"
  else
    add_check "windows_localhost_port" "false" "Windows localhost:$REQUESTED_CDP_PORT is not reachable (Windows side)" "Ensure Chrome is running with --remote-debugging-port=$REQUESTED_CDP_PORT" "warning"
  fi
else
  add_check "windows_localhost_port" "false" "Cannot check Windows port (powershell unavailable)" "Install PowerShell or ensure it's in PATH" "warning"
fi

# Check 4: Check WSL can reach CDP on localhost first, then Windows gateway
CDP_HTTP_HOST=""
CDP_HTTP_LABEL=""
if wsl_windows_chrome_http_json_version "127.0.0.1" "$REQUESTED_CDP_PORT" >/dev/null 2>&1; then
  add_check "wsl_localhost_cdp" "true" "WSL can reach CDP on 127.0.0.1:$REQUESTED_CDP_PORT" "" "warning"
  CDP_HTTP_HOST="127.0.0.1"
  CDP_HTTP_LABEL="localhost"
else
  add_check "wsl_localhost_cdp" "false" "WSL cannot reach CDP on 127.0.0.1:$REQUESTED_CDP_PORT" "Try Windows gateway probing or relay" "warning"
fi

if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if wsl_windows_chrome_endpoint_reachable "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT"; then
    add_check "wsl_gateway_port" "true" "WSL can reach Windows gateway $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" "" "warning"
    if [[ -z "$CDP_HTTP_HOST" ]] && wsl_windows_chrome_http_json_version "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT" >/dev/null 2>&1; then
      CDP_HTTP_HOST="$WINDOWS_GATEWAY"
      CDP_HTTP_LABEL="gateway"
    fi
  else
    add_check "wsl_gateway_port" "false" "WSL cannot reach Windows gateway $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT" "Check Windows firewall or start Chrome with --remote-debugging-address=0.0.0.0" "warning"
  fi
else
  add_check "wsl_gateway_port" "false" "Could not determine Windows gateway" "Check WSL network configuration" "warning"
fi

# Check 5: Check /json/version endpoint via preferred reachable host
if [[ -n "$CDP_HTTP_HOST" ]]; then
  if version_json="$(wsl_windows_chrome_http_json_version "$CDP_HTTP_HOST" "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
    add_check "json_version_endpoint" "true" "Successfully retrieved /json/version from $CDP_HTTP_LABEL $CDP_HTTP_HOST:$REQUESTED_CDP_PORT" ""
    if [[ "$VERBOSE" == "true" ]]; then
      log "Version JSON: $version_json"
    fi
  else
    add_check "json_version_endpoint" "false" "Failed to retrieve /json/version from $CDP_HTTP_LABEL $CDP_HTTP_HOST:$REQUESTED_CDP_PORT" "Ensure CDP endpoint is responding correctly"
  fi
else
  add_check "json_version_endpoint" "false" "No reachable CDP HTTP host found" "Start Chrome with fixed CDP port 9222"
fi

# Check 6: Check /json/list endpoint via preferred reachable host
if [[ -n "$CDP_HTTP_HOST" ]]; then
  if list_json="$(wsl_windows_chrome_fetch_url "http://$CDP_HTTP_HOST:$REQUESTED_CDP_PORT/json/list" 2>/dev/null)"; then
    add_check "json_list_endpoint" "true" "Successfully retrieved /json/list from $CDP_HTTP_LABEL $CDP_HTTP_HOST:$REQUESTED_CDP_PORT" "" "warning"
    if [[ "$VERBOSE" == "true" ]]; then
      tab_count="$(echo "$list_json" | python3 -c 'import sys, json; data = json.load(sys.stdin); print(len(data))' 2>/dev/null || echo "unknown")"
      log "Open tabs/pages: $tab_count"
    fi
  else
    add_check "json_list_endpoint" "false" "Failed to retrieve /json/list from $CDP_HTTP_LABEL $CDP_HTTP_HOST:$REQUESTED_CDP_PORT" "Ensure CDP endpoint is responding correctly" "warning"
  fi
else
  add_check "json_list_endpoint" "false" "No reachable CDP HTTP host found" "Start Chrome with fixed CDP port 9222" "warning"
fi

# Check 7: Check relay port (if available)
RELAY_BIND_HOST="$(wsl_windows_chrome_relay_bind_host "$WINDOWS_GATEWAY")"
relay_available="false"
if [[ -n "$RELAY_BIND_HOST" ]]; then
  if wsl_windows_chrome_endpoint_reachable "$RELAY_BIND_HOST" "$RELAY_PORT"; then
    add_check "relay_port" "true" "Relay port $RELAY_BIND_HOST:$RELAY_PORT is reachable" "" "warning"
    relay_available="true"
  else
    add_check "relay_port" "false" "Relay port $RELAY_BIND_HOST:$RELAY_PORT not reachable" "(Optional - only needed if direct attach fails)" "warning"
  fi
else
  add_check "relay_port" "false" "Could not determine relay bind host" "Check WSL network configuration" "warning"
fi

# Check 8: Check WebSocket endpoint via preferred reachable host OR relay
websocket_found="false"
if [[ -n "$CDP_HTTP_HOST" ]]; then
  if ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$CDP_HTTP_HOST" "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
    add_check "websocket_endpoint" "true" "Successfully parsed WebSocket endpoint from /json/version" ""
    websocket_found="true"
    if [[ "$VERBOSE" == "true" ]]; then
      log "WebSocket endpoint: $ws_endpoint"
    fi
  else
    add_check "websocket_endpoint" "false" "Failed to parse WebSocket endpoint from /json/version" "Check if /json/version contains a valid webSocketDebuggerUrl"
  fi
elif [[ "$relay_available" == "true" ]] && ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
  add_check "websocket_endpoint" "true" "Successfully parsed WebSocket endpoint from relay /json/version" ""
  websocket_found="true"
  if [[ "$VERBOSE" == "true" ]]; then
    log "WebSocket endpoint (relay): $ws_endpoint"
  fi
else
  add_check "websocket_endpoint" "false" "No reachable CDP HTTP host found" "Start Chrome with fixed CDP port 9222"
fi

if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]]; then
  STRICT_HEALTHY=true
fi

if [[ "$websocket_found" == "true" ]]; then
  READINESS_READY=true
fi

if [[ "$STRICT" == "true" ]]; then
  OVERALL_SUCCESS="$STRICT_HEALTHY"
else
  OVERALL_SUCCESS="$READINESS_READY"
fi

# Output results
if [[ "$JSON_OUTPUT" == "true" ]]; then
  print_results_json
else
  print_results
fi

if [[ "$OVERALL_SUCCESS" == "true" ]]; then
  exit 0
else
  exit 1
fi
