#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"
RELAY_PORT="${WSL_WINDOWS_CHROME_RELAY_PORT:-39222}"

usage() {
  cat <<'USAGE'
Usage: print_windows_chrome_ws_endpoint.sh [options]

This helper reuses the fixed persistent agent browser profile. If the
dedicated profile advertises a different active port in DevToolsActivePort,
the helper reports that mismatch but will not switch ports.

Options:
  --browser <chrome|edge>  Select the Windows browser family
  --port <port>            Override the Windows CDP port (default: 9222; use 9222 unless explicitly required)
  --user-data-dir <path>   Override the Windows automation user-data-dir
  --relay-port <port>      Override the WSL-visible relay port
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
    --relay-port)
      RELAY_PORT="$2"
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
REQUESTED_CDP_PORT="$CDP_PORT"
DISCOVERED_CDP_PORT=''
ACTIVE_PORT_PATH=''
RESOLVED_CDP_PORT="$CDP_PORT"
PORT_MISMATCH=false

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

This helper will not switch to that port automatically. Relaunch the dedicated
automation browser with --remote-debugging-port=$REQUESTED_CDP_PORT and
--profile-directory=Default.
EOF
  fi
}

if ! wsl_windows_chrome_has_cmd python3; then
  echo "python3 not found; this helper requires python3 for CDP endpoint parsing." >&2
  exit 1
fi

if ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint '127.0.0.1' "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
  printf '%s\n' "$ws_endpoint"
  exit 0
fi

WINDOWS_GATEWAY="$(wsl_windows_chrome_gateway)"
RELAY_BIND_HOST="$(wsl_windows_chrome_relay_bind_host "$WINDOWS_GATEWAY")"

if [[ -n "$WINDOWS_GATEWAY" ]] && ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$WINDOWS_GATEWAY" "$REQUESTED_CDP_PORT" 2>/dev/null)"; then
  printf '%s\n' "$ws_endpoint"
  exit 0
fi

mapfile -t devtools_lines < <(wsl_windows_chrome_read_profile_port "$BROWSER" "$WINDOWS_USER_DATA_DIR" | sed '/^$/d')
if [[ "${#devtools_lines[@]}" -ge 4 ]]; then
  ACTIVE_PORT_PATH="${devtools_lines[2]}"
  DISCOVERED_CDP_PORT="${devtools_lines[3]}"
fi

if [[ -n "$DISCOVERED_CDP_PORT" && "$DISCOVERED_CDP_PORT" != "$REQUESTED_CDP_PORT" ]]; then
  PORT_MISMATCH=true
  RESOLVED_CDP_PORT="$REQUESTED_CDP_PORT"
fi

if [[ "$PORT_MISMATCH" != true && -n "$RELAY_BIND_HOST" ]] && ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
  printf '%s\n' "$ws_endpoint"
  exit 0
fi

if [[ "$PORT_MISMATCH" == true ]]; then
  echo "Dedicated profile is active on port $DISCOVERED_CDP_PORT, but fixed agent CDP port $REQUESTED_CDP_PORT is required." >&2
  print_setup_hint >&2
  exit 1
fi

if [[ -z "$RELAY_BIND_HOST" ]]; then
  echo "Unable to determine a relay bind host from WSL networking." >&2
  print_setup_hint >&2
  exit 1
fi

if ! wsl_windows_chrome_has_powershell; then
  echo "powershell.exe not found; relay-assisted attach is unavailable." >&2
  print_setup_hint >&2
  exit 1
fi

bash "$SCRIPT_DIR/start_windows_chrome_cdp_relay.sh" "$RELAY_PORT" "$RESOLVED_CDP_PORT" "$RELAY_BIND_HOST" >/dev/null

if ! ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$RELAY_BIND_HOST" "$RELAY_PORT" 2>/dev/null)"; then
  echo "Relay did not become reachable on $RELAY_BIND_HOST:$RELAY_PORT." >&2
  print_setup_hint >&2
  exit 1
fi

printf '%s\n' "$ws_endpoint"
