#!/usr/bin/env bash

wsl_windows_chrome_log() {
  printf '[wsl-windows-chrome] %s\n' "$*"
}

wsl_windows_chrome_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

wsl_windows_chrome_powershell_exe() {
  local candidate

  if command -v powershell.exe >/dev/null 2>&1; then
    command -v powershell.exe
    return 0
  fi

  for candidate in \
    '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' \
    '/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe'
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

wsl_windows_chrome_has_powershell() {
  wsl_windows_chrome_powershell_exe >/dev/null 2>&1
}

wsl_windows_chrome_powershell() {
  local powershell_exe

  powershell_exe="$(wsl_windows_chrome_powershell_exe)" || return 127
  "$powershell_exe" -NoProfile -ExecutionPolicy Bypass "$@"
}

wsl_windows_chrome_normalize_browser() {
  case "$1" in
    chrome | google-chrome | '')
      printf 'chrome\n'
      ;;
    edge | msedge)
      printf 'edge\n'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

wsl_windows_chrome_escape_ps_single_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

wsl_windows_chrome_gateway() {
  ip route | awk '/default/ {print $3; exit}'
}

wsl_windows_chrome_browser_label() {
  case "$(wsl_windows_chrome_normalize_browser "$1")" in
    chrome)
      printf 'Google Chrome\n'
      ;;
    edge)
      printf 'Microsoft Edge\n'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

wsl_windows_chrome_user_data_dir() {
  local browser
  local override="${2:-}"

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  browser="$(wsl_windows_chrome_normalize_browser "$1")"
  case "$browser" in
    chrome)
      printf '%s\n' 'C:\chrome-wsl-automation'
      ;;
    edge)
      printf '%s\n' 'C:\edge-wsl-automation'
      ;;
    *)
      return 1
      ;;
  esac
}

wsl_windows_chrome_windows_exe_candidates() {
  case "$(wsl_windows_chrome_normalize_browser "$1")" in
    chrome)
      printf '%s\n' '%ProgramFiles%\Google\Chrome\Application\chrome.exe'
      printf '%s\n' '%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe'
      ;;
    edge)
      printf '%s\n' '%ProgramFiles%\Microsoft\Edge\Application\msedge.exe'
      printf '%s\n' '%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe'
      ;;
    *)
      return 1
      ;;
  esac
}

wsl_windows_chrome_read_devtools() {
  local browser="$1"
  local user_data_dir="${2:-}"
  local resolved_dir
  local escaped_browser
  local escaped_dir
  local ps

  resolved_dir="$(wsl_windows_chrome_user_data_dir "$browser" "$user_data_dir")" || return 1
  escaped_browser="$(wsl_windows_chrome_escape_ps_single_quote "$browser")"
  escaped_dir="$(wsl_windows_chrome_escape_ps_single_quote "$resolved_dir")"

  ps=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$browser = '__BROWSER__'
$userDataDirInput = '__USER_DATA_DIR__'

if ([System.IO.Path]::IsPathRooted($userDataDirInput)) {
  $userDataDir = $userDataDirInput
} else {
  $userDataDir = Join-Path $env:LOCALAPPDATA $userDataDirInput
}

$activePortPath = Join-Path $userDataDir 'DevToolsActivePort'
if (Test-Path $activePortPath) {
  $lines = @(Get-Content $activePortPath | Where-Object { $_ -and $_.Trim() -ne '' })
  if ($lines.Count -ge 2) {
    Write-Output $browser
    Write-Output $userDataDir
    Write-Output $activePortPath
    Write-Output $lines[0]
    Write-Output $lines[1]
  }
}
PS1
)

  ps="${ps//__BROWSER__/$escaped_browser}"
  ps="${ps//__USER_DATA_DIR__/$escaped_dir}"

  wsl_windows_chrome_powershell -Command "$ps" | tr -d '\r'
}

wsl_windows_chrome_read_process_port() {
  local browser="$1"
  local user_data_dir="${2:-}"
  local resolved_dir
  local escaped_browser
  local escaped_dir
  local ps

  resolved_dir="$(wsl_windows_chrome_user_data_dir "$browser" "$user_data_dir")" || return 1
  escaped_browser="$(wsl_windows_chrome_escape_ps_single_quote "$browser")"
  escaped_dir="$(wsl_windows_chrome_escape_ps_single_quote "$resolved_dir")"

  ps=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$browser = '__BROWSER__'
$userDataDirInput = '__USER_DATA_DIR__'

if ([System.IO.Path]::IsPathRooted($userDataDirInput)) {
  $userDataDir = $userDataDirInput
} else {
  $userDataDir = Join-Path $env:LOCALAPPDATA $userDataDirInput
}

$processPattern = switch ($browser) {
  'edge' { '^msedge(.exe)?$' }
  default { '^chrome(.exe)?$' }
}

$escapedUserDataDir = [regex]::Escape($userDataDir)

Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -match $processPattern -and
    $_.CommandLine -match '--remote-debugging-port=(\d+)' -and
    $_.CommandLine -match $escapedUserDataDir
  } |
  Select-Object -First 1 |
  ForEach-Object {
    $match = [regex]::Match($_.CommandLine, '--remote-debugging-port=(\d+)')
    if ($match.Success) {
      Write-Output $browser
      Write-Output $userDataDir
      Write-Output ("process:" + $_.ProcessId)
      Write-Output $match.Groups[1].Value
      Write-Output ''
    }
  }
PS1
)

  ps="${ps//__BROWSER__/$escaped_browser}"
  ps="${ps//__USER_DATA_DIR__/$escaped_dir}"

  wsl_windows_chrome_powershell -Command "$ps" | tr -d '\r'
}

wsl_windows_chrome_read_profile_port() {
  local browser="$1"
  local user_data_dir="${2:-}"
  local output

  output="$(wsl_windows_chrome_read_devtools "$browser" "$user_data_dir" | sed '/^$/d')" || true
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
    return 0
  fi

  wsl_windows_chrome_read_process_port "$browser" "$user_data_dir"
}

wsl_windows_chrome_endpoint_reachable() {
  local host="$1"
  local port="$2"

  timeout 2 bash -lc "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1
}

wsl_windows_chrome_fetch_url() {
  local url="$1"

  if wsl_windows_chrome_has_cmd curl; then
    curl -fsSL --max-time 3 "$url"
    return $?
  fi

  if wsl_windows_chrome_has_cmd python3; then
    URL="$url" python3 - <<'PY'
import os
import sys
import urllib.request

url = os.environ["URL"]
with urllib.request.urlopen(url, timeout=3) as response:
    sys.stdout.write(response.read().decode("utf-8"))
PY
    return $?
  fi

  return 127
}

wsl_windows_chrome_http_json_version() {
  local host="$1"
  local port="$2"

  wsl_windows_chrome_fetch_url "http://$host:$port/json/version"
}

wsl_windows_chrome_http_ws_endpoint() {
  local host="$1"
  local port="$2"
  local json_payload

  json_payload="$(wsl_windows_chrome_http_json_version "$host" "$port")" || return 1

  JSON_PAYLOAD="$json_payload" python3 - "$host" "$port" <<'PY'
import json
import os
import sys
from urllib.parse import urlparse

host, port = sys.argv[1], sys.argv[2]
data = json.loads(os.environ["JSON_PAYLOAD"])
websocket_url = data.get("webSocketDebuggerUrl") or ""
path = urlparse(websocket_url).path or ""
if not path:
    raise SystemExit(1)
print(f"ws://{host}:{port}{path}")
PY
}

wsl_windows_chrome_cdp_probe() {
  local endpoint="$1"
  local escaped_endpoint
  local ps

  escaped_endpoint="$(wsl_windows_chrome_escape_ps_single_quote "$endpoint")"
  ps=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$endpoint = '__ENDPOINT__'
$req = $null

try {
  $req = [System.Net.WebSockets.ClientWebSocket]::new()
  $req.ConnectAsync([Uri]$endpoint, [Threading.CancellationToken]::None).Wait(3000) | Out-Null
  if ($req.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
    exit 1
  }

  $payload = [System.Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Browser.getVersion"}')
  $req.SendAsync([ArraySegment[byte]]::new($payload), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()

  $buffer = New-Object byte[] 4096
  $recvTask = $req.ReceiveAsync([ArraySegment[byte]]::new($buffer), [Threading.CancellationToken]::None)
  $recvTask.Wait(3000) | Out-Null
  if (-not $recvTask.IsCompleted) {
    exit 1
  }

  $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $recvTask.Result.Count)
  if ($text -match '"protocolVersion"') {
    exit 0
  }
  exit 1
} catch {
  exit 1
} finally {
  if ($req) {
    $req.Dispose()
  }
}
PS1
)

  ps="${ps//__ENDPOINT__/$escaped_endpoint}"
  wsl_windows_chrome_powershell -Command "$ps" >/dev/null 2>&1
}

wsl_windows_chrome_wait_for_endpoint() {
  local host="$1"
  local port="$2"
  local wait_seconds="$3"
  local poll_seconds="$4"
  local attempts
  local i

  attempts="$(awk "BEGIN { n = $wait_seconds / $poll_seconds; if (n < 1) n = 1; print int(n + 0.999) }")"

  for ((i = 0; i < attempts; i++)); do
    if wsl_windows_chrome_endpoint_reachable "$host" "$port"; then
      return 0
    fi
    sleep "$poll_seconds"
  done

  return 1
}

wsl_windows_chrome_wait_for_session() {
  local session="$1"
  local wait_seconds="$2"
  local poll_seconds="$3"
  local attempts
  local i

  attempts="$(awk "BEGIN { n = $wait_seconds / $poll_seconds; if (n < 1) n = 1; print int(n + 0.999) }")"

  for ((i = 0; i < attempts; i++)); do
    if playwright-cli "-s=$session" snapshot >/dev/null 2>&1; then
      return 0
    fi
    sleep "$poll_seconds"
  done

  return 1
}

wsl_windows_chrome_session_active() {
  local session="$1"
  playwright-cli "-s=$session" snapshot >/dev/null 2>&1
}

wsl_windows_chrome_close_session() {
  local session="$1"
  playwright-cli "-s=$session" close >/dev/null 2>&1 || true
}

wsl_windows_chrome_relay_bind_host() {
  local gateway="$1"
  local override="${WSL_WINDOWS_CHROME_RELAY_BIND_HOST:-}"

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  printf '%s\n' "$gateway"
}

wsl_windows_chrome_relay_key() {
  local bind_host="$1"
  local listen_port="$2"
  local target_port="$3"

  printf '%s_%s_%s' "$bind_host" "$listen_port" "$target_port" | tr -c '[:alnum:]' '_'
}
