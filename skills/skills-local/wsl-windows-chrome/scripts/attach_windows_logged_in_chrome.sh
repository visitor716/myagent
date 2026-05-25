#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SESSION="${PLAYWRIGHT_CLI_SESSION:-wsl-windows-chrome}"
URL=""
ATTACH_ONLY=true  # 默认启用 attach-only，禁止 fallback
HEADED=false
STATUS_ONLY=false
JSON_OUTPUT=false
VERBOSE=false
BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"
RELAY_PORT="${WSL_WINDOWS_CHROME_RELAY_PORT:-39222}"
ATTACH_WAIT_SECONDS="${WSL_WINDOWS_CHROME_ATTACH_WAIT_SECONDS:-40}"
ATTACH_POLL_SECONDS="${WSL_WINDOWS_CHROME_ATTACH_POLL_SECONDS:-0.25}"
REUSE_EXISTING_TARGET="${WSL_WINDOWS_CHROME_REUSE_EXISTING_TARGET:-true}"

usage() {
  cat <<'USAGE'
Usage: attach_windows_logged_in_chrome.sh [options]

Attach from WSL to a dedicated Windows Chrome or Edge automation browser.
Recommended Windows launch flags:
  --remote-debugging-port=9222
  --user-data-dir=C:\chrome-wsl-automation
  --profile-directory=Default

This helper is strict about reusing the persistent agent browser profile. If
the dedicated profile advertises a different active port in DevToolsActivePort,
the helper reports that mismatch for diagnosis but will not switch ports.

IMPORTANT: This helper will NOT fall back to a fresh browser session.
If the Windows automation browser CDP endpoint is not reachable, it will
fail immediately with diagnostic information and setup instructions.

Options:
  --browser <chrome|edge>  Select the Windows browser family
  --session <name>         Bind playwright-cli commands to a named session
  --port <port>            Override the Windows CDP port (default: 9222; use 9222 unless explicitly required)
  --user-data-dir <path>   Override the Windows automation user-data-dir (default: C:\chrome-wsl-automation)
  --url <url>              Navigate after attach or open
  --no-reuse-existing-target
                          Do not activate an already-open matching target URL before attach
  --relay-port <port>      Override the WSL-visible relay port (default: 39222)
  --attach-only            (Ignored, default behavior) Always fail instead of opening fresh browser
  --status                 Print detection and reachability status without attaching
  --json                   Print status as JSON (use with --status)
  --verbose                Print extra diagnostics
  --headed                 (Ignored, no fallback)
  --help                   Show this help
USAGE
}

log() {
  wsl_windows_chrome_log "$@"
}

print_setup_hint() {
  cat <<EOF
Start $BROWSER_LABEL on Windows with:
  --remote-debugging-port=$REQUESTED_CDP_PORT
  --user-data-dir="$WINDOWS_USER_DATA_DIR_RESOLVED"
  --profile-directory=Default

Launcher helper:
  bash "$SCRIPT_DIR/print_windows_automation_browser_launcher.sh" --browser "$BROWSER" --port "$REQUESTED_CDP_PORT" --user-data-dir "$WINDOWS_USER_DATA_DIR_RESOLVED"
EOF

  if [[ -n "$DISCOVERED_CDP_PORT" && "$DISCOVERED_CDP_PORT" != "$REQUESTED_CDP_PORT" ]]; then
    cat <<EOF

Detected active automation browser port from "$ACTIVE_PORT_PATH":
  $DISCOVERED_CDP_PORT

This skill will not switch to that port automatically. Relaunch the dedicated
automation browser with --remote-debugging-port=$REQUESTED_CDP_PORT and
--profile-directory=Default so login state stays in the canonical agent profile.
EOF
  fi
}

print_status() {
  cat <<EOF
browser=$BROWSER
browser_label=$BROWSER_LABEL
session=$SESSION
cdp_port=$CDP_PORT
requested_cdp_port=$REQUESTED_CDP_PORT
resolved_cdp_port=$RESOLVED_CDP_PORT
discovered_cdp_port=$DISCOVERED_CDP_PORT
active_port_path=$ACTIVE_PORT_PATH
automation_user_data_dir=$WINDOWS_USER_DATA_DIR_RESOLVED
windows_gateway=$WINDOWS_GATEWAY
relay_bind_host=$RELAY_BIND_HOST
localhost_endpoint=$LOCALHOST_WS_ENDPOINT
gateway_endpoint=$GATEWAY_WS_ENDPOINT
direct_endpoint=$DIRECT_WS_ENDPOINT
relay_endpoint=$RELAY_WS_ENDPOINT
preferred_endpoint=$PREFERRED_WS_ENDPOINT
preferred_mode=$PREFERRED_MODE
direct_reachable=$DIRECT_REACHABLE
relay_reachable=$RELAY_REACHABLE
local_cdp_ready=$LOCAL_CDP_READY
gateway_cdp_ready=$GATEWAY_CDP_READY
relay_cdp_ready=$RELAY_CDP_READY
EOF
}

print_status_json() {
  STATUS_OK_ENV="$STATUS_OK" \
  BROWSER_ENV="$BROWSER" \
  BROWSER_LABEL_ENV="$BROWSER_LABEL" \
  SESSION_ENV="$SESSION" \
  CDP_PORT_ENV="$CDP_PORT" \
  REQUESTED_CDP_PORT_ENV="$REQUESTED_CDP_PORT" \
  RESOLVED_CDP_PORT_ENV="$RESOLVED_CDP_PORT" \
  DISCOVERED_CDP_PORT_ENV="$DISCOVERED_CDP_PORT" \
  ACTIVE_PORT_PATH_ENV="$ACTIVE_PORT_PATH" \
  WINDOWS_USER_DATA_DIR_ENV="$WINDOWS_USER_DATA_DIR_RESOLVED" \
  WINDOWS_GATEWAY_ENV="$WINDOWS_GATEWAY" \
  RELAY_BIND_HOST_ENV="$RELAY_BIND_HOST" \
  LOCALHOST_ENDPOINT_ENV="$LOCALHOST_WS_ENDPOINT" \
  GATEWAY_ENDPOINT_ENV="$GATEWAY_WS_ENDPOINT" \
  DIRECT_ENDPOINT_ENV="$DIRECT_WS_ENDPOINT" \
  RELAY_ENDPOINT_ENV="$RELAY_WS_ENDPOINT" \
  PREFERRED_ENDPOINT_ENV="$PREFERRED_WS_ENDPOINT" \
  PREFERRED_MODE_ENV="$PREFERRED_MODE" \
  DIRECT_REACHABLE_ENV="$DIRECT_REACHABLE" \
  RELAY_REACHABLE_ENV="$RELAY_REACHABLE" \
  LOCAL_CDP_READY_ENV="$LOCAL_CDP_READY" \
  GATEWAY_CDP_READY_ENV="$GATEWAY_CDP_READY" \
  RELAY_CDP_READY_ENV="$RELAY_CDP_READY" \
  STATUS_ERROR_ENV="$STATUS_ERROR" \
  STATUS_ERROR_PRESENT_ENV="$STATUS_ERROR_PRESENT" \
  python3 - <<'PY'
import json
import os

def to_bool(value: str) -> bool:
    return value.lower() == "true"

data = {
    "ok": to_bool(os.environ["STATUS_OK_ENV"]),
    "browser": os.environ["BROWSER_ENV"],
    "browser_label": os.environ["BROWSER_LABEL_ENV"],
    "session": os.environ["SESSION_ENV"],
    "cdp_port": int(os.environ["CDP_PORT_ENV"]),
    "requested_cdp_port": int(os.environ["REQUESTED_CDP_PORT_ENV"]),
    "resolved_cdp_port": int(os.environ["RESOLVED_CDP_PORT_ENV"]),
    "discovered_cdp_port": int(os.environ["DISCOVERED_CDP_PORT_ENV"]) if os.environ["DISCOVERED_CDP_PORT_ENV"] else None,
    "active_port_path": os.environ["ACTIVE_PORT_PATH_ENV"] or None,
    "automation_user_data_dir": os.environ["WINDOWS_USER_DATA_DIR_ENV"],
    "windows_gateway": os.environ["WINDOWS_GATEWAY_ENV"],
    "relay_bind_host": os.environ["RELAY_BIND_HOST_ENV"],
    "localhost_endpoint": os.environ["LOCALHOST_ENDPOINT_ENV"],
    "gateway_endpoint": os.environ["GATEWAY_ENDPOINT_ENV"],
    "direct_endpoint": os.environ["DIRECT_ENDPOINT_ENV"],
    "relay_endpoint": os.environ["RELAY_ENDPOINT_ENV"],
    "preferred_endpoint": os.environ["PREFERRED_ENDPOINT_ENV"],
    "preferred_mode": os.environ["PREFERRED_MODE_ENV"],
    "direct_reachable": to_bool(os.environ["DIRECT_REACHABLE_ENV"]),
    "relay_reachable": to_bool(os.environ["RELAY_REACHABLE_ENV"]),
    "local_cdp_ready": to_bool(os.environ["LOCAL_CDP_READY_ENV"]),
    "gateway_cdp_ready": to_bool(os.environ["GATEWAY_CDP_READY_ENV"]),
    "relay_cdp_ready": to_bool(os.environ["RELAY_CDP_READY_ENV"]),
    "error": os.environ["STATUS_ERROR_ENV"] if to_bool(os.environ["STATUS_ERROR_PRESENT_ENV"]) else None,
}
print(json.dumps(data, ensure_ascii=False))
PY
}

fail_or_fallback() {
  local reason="$1"

  log "$reason"
  print_setup_hint >&2

  # 输出详细的失败信息和诊断命令
  {
    echo ""
    echo "--- 诊断信息 ---"
    echo ""
    echo "当前检测端口: $REQUESTED_CDP_PORT"
    echo "当前尝试连接地址:"
    echo "  - 127.0.0.1:$REQUESTED_CDP_PORT"
    echo "  - $WINDOWS_GATEWAY:$REQUESTED_CDP_PORT"
    echo "  - $RELAY_BIND_HOST:$RELAY_PORT (relay)"
    echo ""
    echo "失败原因: Windows Chrome CDP endpoint 不可达"
    echo ""
    echo "--- Windows Chrome 启动命令 (PowerShell) ---"
    echo ""
    printf '$chrome = "$env:ProgramFiles\\Google\\Chrome\\Application\\chrome.exe"\n'
    printf 'if (!(Test-Path $chrome)) {\n'
    printf '  $chrome = "${env:ProgramFiles(x86)}\\Google\\Chrome\\Application\\chrome.exe"\n'
    printf '}\n'
    printf 'if (!(Test-Path $chrome)) {\n'
    printf '  throw "Chrome not found"\n'
    printf '}\n'
    printf 'Start-Process $chrome -ArgumentList @(\n'
    printf '  "--remote-debugging-address=0.0.0.0",\n'
    printf '  "--remote-debugging-port=%s",\n' "$REQUESTED_CDP_PORT"
    printf '  "--user-data-dir=\"%s\"",\n' "$WINDOWS_USER_DATA_DIR_RESOLVED"
    printf '  "--profile-directory=Default",\n'
    printf '  "--new-window"'
    if [[ -n "$URL" ]]; then
      printf ',\n  "%s"' "$URL"
    fi
    printf '\n)\n'
    echo ""
    echo "--- CDP 验证命令 ---"
    echo ""
    echo "# Windows PowerShell 侧验证:"
    printf 'Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:%s/json/version"\n' "$REQUESTED_CDP_PORT"
    echo ""
    echo "# WSL 侧验证:"
    cat <<WSL_VERIFY
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command 'try { (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$REQUESTED_CDP_PORT/json/version").Content; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }'
WSL_VERIFY
    echo ""
    echo ""
    echo "--- 重新运行 attach 命令 ---"
    echo ""
    printf 'bash "%s/attach_windows_logged_in_chrome.sh" --browser "%s" --port "%s" --user-data-dir "%s"' "$SCRIPT_DIR" "$BROWSER" "$REQUESTED_CDP_PORT" "$WINDOWS_USER_DATA_DIR_RESOLVED"
    if [[ -n "$URL" ]]; then
      printf ' --url "%s"' "$URL"
    fi
    printf ' --session "%s"' "$SESSION"
    echo ""
    echo ""
  } >&2

  return 1
}

activate_existing_target_page() {
  local endpoint="$1"
  local http_base
  local target_lines=()
  local target_id
  local target_url
  local target_title
  local match_reason

  if [[ -z "$URL" || "$REUSE_EXISTING_TARGET" != true ]]; then
    return 1
  fi

  http_base="$(wsl_windows_chrome_http_base_from_ws_endpoint "$endpoint")" || return 1
  mapfile -t target_lines < <(wsl_windows_chrome_find_target_tab "$http_base" "$URL" 2>/dev/null) || return 1
  if [[ "${#target_lines[@]}" -lt 2 || -z "${target_lines[0]}" ]]; then
    return 1
  fi

  target_id="${target_lines[0]}"
  target_url="${target_lines[1]}"
  target_title="${target_lines[2]:-}"
  match_reason="${target_lines[3]:-matched}"

  if ! wsl_windows_chrome_activate_target_tab "$http_base" "$target_id"; then
    return 1
  fi

  log "Found existing target page for $URL; activated tab $target_id and skipped navigation ($match_reason)."
  if [[ "$VERBOSE" == true ]]; then
    log "Existing target URL: $target_url"
    if [[ -n "$target_title" ]]; then
      log "Existing target title: $target_title"
    fi
  fi
  return 0
}

attach_endpoint() {
  local endpoint="$1"
  local label="$2"
  local log_file
  local attach_pid
  local reused_target=false

  if wsl_windows_chrome_session_active "$SESSION"; then
    log "Closing existing playwright-cli session '$SESSION' before attach to avoid stale-session collisions."
    wsl_windows_chrome_close_session "$SESSION"
  fi

  if activate_existing_target_page "$endpoint"; then
    reused_target=true
  fi

  log "Trying playwright-cli attach via $endpoint"
  log_file="$(mktemp)"
  nohup playwright-cli attach --cdp="$endpoint" --session="$SESSION" >"$log_file" 2>&1 &
  attach_pid=$!

  if wsl_windows_chrome_wait_for_session "$SESSION" "$ATTACH_WAIT_SECONDS" "$ATTACH_POLL_SECONDS"; then
    disown "$attach_pid" >/dev/null 2>&1 || true
    rm -f "$log_file"
    if [[ -n "$URL" && "$reused_target" != true ]]; then
      local command_timeout="${WSL_WINDOWS_CHROME_PLAYWRIGHT_COMMAND_TIMEOUT_SECONDS:-15}"
      if ! timeout "$command_timeout" playwright-cli "-s=$SESSION" goto "$URL"; then
        log "Attached through $label, but navigation to $URL did not complete within ${command_timeout}s."
        wsl_windows_chrome_close_session "$SESSION"
        return 1
      fi
    fi
    log "Attached through $label"
    return 0
  fi

  if kill -0 "$attach_pid" >/dev/null 2>&1; then
    kill "$attach_pid" >/dev/null 2>&1 || true
    wait "$attach_pid" 2>/dev/null || true
  fi

  wsl_windows_chrome_close_session "$SESSION"
  sed 's/^/[wsl-windows-chrome] /' "$log_file" >&2 || true
  rm -f "$log_file"
  return 1
}

probe_candidate_port() {
  local port="$1"
  local source_label="$2"
  local source_mode_prefix=''

  if [[ "$source_label" != "requested" ]]; then
    source_mode_prefix="${source_label}-"
  fi

  if [[ "$VERBOSE" == true ]]; then
    log "Checking localhost CDP endpoint on 127.0.0.1:$port"
  fi
  if LOCALHOST_WS_ENDPOINT="$(wsl_windows_chrome_http_ws_endpoint '127.0.0.1' "$port" 2>/dev/null)"; then
    LOCAL_CDP_READY=true
    DIRECT_REACHABLE=true
    DIRECT_WS_ENDPOINT="$LOCALHOST_WS_ENDPOINT"
    PREFERRED_WS_ENDPOINT="$LOCALHOST_WS_ENDPOINT"
    PREFERRED_MODE="${source_mode_prefix}localhost"
    RESOLVED_CDP_PORT="$port"
    CDP_PORT="$port"
    return 0
  fi

  if [[ -n "$WINDOWS_GATEWAY" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      log "Checking Windows gateway CDP endpoint on $WINDOWS_GATEWAY:$port"
    fi
    if GATEWAY_WS_ENDPOINT="$(wsl_windows_chrome_http_ws_endpoint "$WINDOWS_GATEWAY" "$port" 2>/dev/null)"; then
      GATEWAY_CDP_READY=true
      DIRECT_REACHABLE=true
      DIRECT_WS_ENDPOINT="$GATEWAY_WS_ENDPOINT"
      PREFERRED_WS_ENDPOINT="$GATEWAY_WS_ENDPOINT"
      PREFERRED_MODE="${source_mode_prefix}gateway"
      RESOLVED_CDP_PORT="$port"
      CDP_PORT="$port"
      return 0
    fi
  fi

  return 1
}

while (($#)); do
  case "$1" in
    --browser)
      BROWSER="$2"
      shift 2
      ;;
    --session)
      SESSION="$2"
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
    --url)
      URL="$2"
      shift 2
      ;;
    --no-reuse-existing-target)
      REUSE_EXISTING_TARGET=false
      shift
      ;;
    --relay-port)
      RELAY_PORT="$2"
      shift 2
      ;;
    --attach-only)
      ATTACH_ONLY=true
      shift
      ;;
    --status)
      STATUS_ONLY=true
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
    --headed)
      HEADED=true
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
STATUS_OK=false
STATUS_ERROR=''
STATUS_ERROR_PRESENT=false
WINDOWS_GATEWAY="$(wsl_windows_chrome_gateway)"
RELAY_BIND_HOST="$(wsl_windows_chrome_relay_bind_host "$WINDOWS_GATEWAY")"
ACTIVE_PORT_PATH=''
DISCOVERED_CDP_PORT=''
RESOLVED_CDP_PORT="$CDP_PORT"
LOCALHOST_WS_ENDPOINT=''
GATEWAY_WS_ENDPOINT=''
DIRECT_WS_ENDPOINT=''
RELAY_WS_ENDPOINT=''
PREFERRED_WS_ENDPOINT=''
PREFERRED_MODE=''
DIRECT_REACHABLE=false
RELAY_REACHABLE=false
LOCAL_CDP_READY=false
GATEWAY_CDP_READY=false
RELAY_CDP_READY=false
PORT_MISMATCH=false

if [[ "$JSON_OUTPUT" == true && "$STATUS_ONLY" == false ]]; then
  echo '--json currently requires --status.' >&2
  exit 1
fi

if ! wsl_windows_chrome_has_cmd python3; then
  echo 'python3 not found in PATH; this helper needs python3 for CDP endpoint parsing.' >&2
  exit 1
fi

if [[ "$STATUS_ONLY" == false ]] && ! wsl_windows_chrome_has_cmd playwright-cli; then
  echo 'playwright-cli not found in PATH.' >&2
  exit 1
fi

probe_candidate_port "$REQUESTED_CDP_PORT" 'requested' || true

mapfile -t devtools_lines < <(wsl_windows_chrome_read_profile_port "$BROWSER" "$WINDOWS_USER_DATA_DIR" | sed '/^$/d')
if [[ "${#devtools_lines[@]}" -ge 4 ]]; then
  ACTIVE_PORT_PATH="${devtools_lines[2]}"
  DISCOVERED_CDP_PORT="${devtools_lines[3]}"
fi

if [[ -n "$DISCOVERED_CDP_PORT" && "$DISCOVERED_CDP_PORT" != "$REQUESTED_CDP_PORT" && "$DIRECT_REACHABLE" != true ]]; then
  PORT_MISMATCH=true
  if [[ "$VERBOSE" == true ]]; then
    log "Dedicated profile reports active port $DISCOVERED_CDP_PORT from $ACTIVE_PORT_PATH, but fixed agent port is $REQUESTED_CDP_PORT; not switching ports."
  fi
fi

if [[ "$PORT_MISMATCH" != true && -n "$RELAY_BIND_HOST" ]] && RELAY_WS_ENDPOINT="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
  RELAY_REACHABLE=true
  RELAY_CDP_READY=true
  if [[ -z "$PREFERRED_WS_ENDPOINT" ]]; then
    PREFERRED_WS_ENDPOINT="$RELAY_WS_ENDPOINT"
    if [[ "$RESOLVED_CDP_PORT" == "$REQUESTED_CDP_PORT" ]]; then
      PREFERRED_MODE='relay'
    else
      PREFERRED_MODE='profile-relay'
    fi
  fi
fi

if [[ "$STATUS_ONLY" == true ]]; then
  if [[ "$DIRECT_REACHABLE" == true || "$RELAY_CDP_READY" == true ]]; then
    STATUS_OK=true
  else
    if [[ -n "$DISCOVERED_CDP_PORT" && "$DISCOVERED_CDP_PORT" != "$REQUESTED_CDP_PORT" ]]; then
      STATUS_ERROR="$BROWSER_LABEL profile is active on port $DISCOVERED_CDP_PORT, but this skill requires fixed agent CDP port $REQUESTED_CDP_PORT."
    else
      STATUS_ERROR="$BROWSER_LABEL is not exposing a reachable CDP endpoint on requested port $REQUESTED_CDP_PORT from WSL."
    fi
    STATUS_ERROR_PRESENT=true
  fi

  if [[ "$JSON_OUTPUT" == true ]]; then
    print_status_json
  else
    print_status
    if [[ "$STATUS_OK" != true ]]; then
      print_setup_hint >&2
    fi
  fi

  if [[ "$STATUS_OK" == true ]]; then
    exit 0
  fi

  exit 1
fi

declare -a attach_endpoints=()
declare -a attach_labels=()

if [[ "$LOCAL_CDP_READY" == true ]]; then
  attach_endpoints+=("$LOCALHOST_WS_ENDPOINT")
  attach_labels+=('localhost CDP attach')
fi

if [[ "$GATEWAY_CDP_READY" == true && "$GATEWAY_WS_ENDPOINT" != "$LOCALHOST_WS_ENDPOINT" ]]; then
  attach_endpoints+=("$GATEWAY_WS_ENDPOINT")
  attach_labels+=('gateway CDP attach')
fi

for ((i = 0; i < ${#attach_endpoints[@]}; i++)); do
  if attach_endpoint "${attach_endpoints[$i]}" "${attach_labels[$i]}"; then
    log "Attached to the dedicated Windows automation browser on ${attach_endpoints[$i]}"
    exit 0
  fi
done

RELAY_TARGET_CDP_PORT="$RESOLVED_CDP_PORT"

if [[ "$PORT_MISMATCH" != true && -n "$RELAY_BIND_HOST" ]]; then
  if ! wsl_windows_chrome_has_powershell; then
    fail_or_fallback 'Direct CDP attach failed, and powershell.exe is unavailable so relay-assisted attach cannot be started.'
    exit $?
  fi

  log "Direct attach is unavailable or failed; starting relay for port $RELAY_TARGET_CDP_PORT on $RELAY_BIND_HOST:$RELAY_PORT."
  bash "$SCRIPT_DIR/start_windows_chrome_cdp_relay.sh" "$RELAY_PORT" "$RELAY_TARGET_CDP_PORT" "$RELAY_BIND_HOST" >/dev/null

  if RELAY_WS_ENDPOINT="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
    RELAY_REACHABLE=true
    RELAY_CDP_READY=true
    PREFERRED_WS_ENDPOINT="$RELAY_WS_ENDPOINT"
    if [[ "$RELAY_TARGET_CDP_PORT" == "$REQUESTED_CDP_PORT" ]]; then
      PREFERRED_MODE='relay'
    else
      PREFERRED_MODE='profile-relay'
    fi
    RESOLVED_CDP_PORT="$RELAY_TARGET_CDP_PORT"
    CDP_PORT="$RELAY_TARGET_CDP_PORT"
  fi
fi

if [[ "$RELAY_CDP_READY" == true ]] && attach_endpoint "$RELAY_WS_ENDPOINT" 'relay-assisted CDP attach'; then
  log "Attached to the dedicated Windows automation browser through relay $RELAY_WS_ENDPOINT"
  exit 0
fi

if [[ "$DIRECT_REACHABLE" == true ]]; then
  fail_or_fallback "A reachable CDP endpoint was detected on port $CDP_PORT, but Playwright attach did not establish a session within ${ATTACH_WAIT_SECONDS}s."
else
  fail_or_fallback "No reachable Windows automation browser CDP endpoint was found on requested port $REQUESTED_CDP_PORT."
fi
