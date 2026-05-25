#!/usr/bin/env bash
set -euo pipefail

HOST="${WSL_WINDOWS_CHROME_CDP_HOST:-127.0.0.1}"
PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"
TIMEOUT_SECONDS="${WSL_WINDOWS_CHROME_CDP_HTTP_TIMEOUT_SECONDS:-5}"
URL=""
KEEP_OPEN=false
TARGET_ID=""

usage() {
  cat <<'USAGE'
Usage: raw_cdp_smoke_test.sh [options]

Create, list, activate, and close a temporary tab through Chrome DevTools HTTP.
This validates browser control without using playwright-cli or a fallback browser.

Options:
  --url <url>       URL to open (default: https://example.com/?wsl_windows_chrome_raw_cdp=<timestamp>)
  --host <host>     CDP HTTP host (default: 127.0.0.1)
  --port <port>     CDP HTTP port (default: 9222)
  --keep-open       Leave the temporary tab open for manual inspection
  --help            Show this help
USAGE
}

cleanup() {
  if [[ "$KEEP_OPEN" != true && -n "$TARGET_ID" ]]; then
    curl -sS --max-time 2 "http://$HOST:$PORT/json/close/$TARGET_ID" >/dev/null 2>&1 || true
  fi
}

json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(sys.argv[2], "")
print(value if value is not None else "")
PY
}

while (($#)); do
  case "$1" in
    --url)
      URL="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --keep-open)
      KEEP_OPEN=true
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

if [[ -z "$URL" ]]; then
  URL="https://example.com/?wsl_windows_chrome_raw_cdp=$(date +%s)"
fi

TMP_DIR="$(mktemp -d /tmp/wsl-windows-chrome-raw-cdp.XXXXXX)"
trap 'cleanup; rm -rf "$TMP_DIR"' EXIT

BASE_URL="http://$HOST:$PORT"
VERSION_FILE="$TMP_DIR/version.json"
NEW_TAB_FILE="$TMP_DIR/new-tab.json"
LIST_FILE="$TMP_DIR/list.json"

curl -sS --max-time "$TIMEOUT_SECONDS" "$BASE_URL/json/version" >"$VERSION_FILE"
WEBSOCKET_URL="$(json_field "$VERSION_FILE" webSocketDebuggerUrl)"
if [[ -z "$WEBSOCKET_URL" ]]; then
  echo "CDP /json/version did not include webSocketDebuggerUrl" >&2
  exit 1
fi

curl -sS --max-time "$TIMEOUT_SECONDS" -X PUT "$BASE_URL/json/new?$URL" >"$NEW_TAB_FILE"
TARGET_ID="$(json_field "$NEW_TAB_FILE" id)"
CREATED_ID="$TARGET_ID"
TARGET_URL="$(json_field "$NEW_TAB_FILE" url)"
TARGET_TYPE="$(json_field "$NEW_TAB_FILE" type)"
TARGET_WS="$(json_field "$NEW_TAB_FILE" webSocketDebuggerUrl)"

if [[ -z "$TARGET_ID" || "$TARGET_TYPE" != "page" ]]; then
  echo "Failed to create page target through raw CDP HTTP" >&2
  exit 1
fi

sleep 2
curl -sS --max-time "$TIMEOUT_SECONDS" "$BASE_URL/json/list" >"$LIST_FILE"
LIST_RESULT="$(python3 - "$LIST_FILE" "$TARGET_ID" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    tabs = json.load(handle)
target_id = sys.argv[2]
matches = [tab for tab in tabs if tab.get("id") == target_id]
print(f"{len(tabs)}:{len(matches)}")
PY
)"
TAB_COUNT="${LIST_RESULT%%:*}"
MATCH_COUNT="${LIST_RESULT##*:}"
if [[ "$MATCH_COUNT" != "1" ]]; then
  echo "Created target was not found in /json/list" >&2
  exit 1
fi

ACTIVATE_RESULT="$(curl -sS --max-time "$TIMEOUT_SECONDS" "$BASE_URL/json/activate/$TARGET_ID")"
if [[ "$ACTIVATE_RESULT" != *"Target activated"* ]]; then
  echo "Unexpected activate result: $ACTIVATE_RESULT" >&2
  exit 1
fi

if [[ "$KEEP_OPEN" == true ]]; then
  CLOSE_RESULT="kept open"
else
  CLOSE_RESULT="$(curl -sS --max-time "$TIMEOUT_SECONDS" "$BASE_URL/json/close/$TARGET_ID")"
  if [[ "$CLOSE_RESULT" != *"Target is closing"* ]]; then
    echo "Unexpected close result: $CLOSE_RESULT" >&2
    exit 1
  fi
  TARGET_ID=""
fi

cat <<EOF
raw_cdp_ready=true
host=$HOST
port=$PORT
created_id=$CREATED_ID
created_url=$TARGET_URL
created_type=$TARGET_TYPE
created_ws_present=$(if [[ -n "$TARGET_WS" ]]; then echo true; else echo false; fi)
tab_count=$TAB_COUNT
activate_result=$ACTIVATE_RESULT
close_result=$CLOSE_RESULT
EOF
