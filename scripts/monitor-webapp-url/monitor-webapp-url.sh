#!/usr/bin/env bash
# Monitor TG_WEBAPP_URL and rotate the quick tunnel after a sustained outage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${TG_GATEWAY_PROJECT_DIR:-$DEFAULT_PROJECT_DIR}"
ENV_FILE="${TG_GATEWAY_ENV_FILE:-$PROJECT_DIR/.env}"

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    fi
}

load_env

LOG_DIR="$PROJECT_DIR/logs/runtime"
LOG_FILE="${WEBAPP_URL_MONITOR_LOG_FILE:-$LOG_DIR/webapp-url-monitor.log}"
STATE_FILE="${WEBAPP_URL_MONITOR_STATE_FILE:-$LOG_DIR/webapp-url-monitor-state.env}"
TUNNEL_LOG_FILE="${WEBAPP_URL_MONITOR_TUNNEL_LOG_FILE:-$LOG_DIR/webapp-tunnel.log}"
TUNNEL_SESSION="${WEBAPP_URL_MONITOR_TUNNEL_SESSION:-tg-webapp-tunnel}"
MONITOR_SESSION="${WEBAPP_URL_MONITOR_SESSION:-tg-webapp-url-monitor}"

INTERVAL_SECONDS="${WEBAPP_URL_MONITOR_INTERVAL_SECONDS:-300}"
FAILURE_SECONDS="${WEBAPP_URL_MONITOR_FAILURE_SECONDS:-3600}"
PUBLIC_TIMEOUT_SECONDS="${WEBAPP_URL_MONITOR_PUBLIC_TIMEOUT_SECONDS:-25}"
LOCAL_TIMEOUT_SECONDS="${WEBAPP_URL_MONITOR_LOCAL_TIMEOUT_SECONDS:-8}"
AUTO_ROTATE="${WEBAPP_URL_MONITOR_AUTO_ROTATE:-1}"
NEW_URL_READY_ATTEMPTS="${WEBAPP_URL_MONITOR_NEW_URL_READY_ATTEMPTS:-18}"

MODE="once"
DRY_RUN=0
FORCE_ROTATE=0

usage() {
    cat <<'EOF'
Usage: scripts/monitor-webapp-url/monitor-webapp-url.sh [--once|--loop|--start|--stop|--status] [options]

Monitors TG_WEBAPP_URL. If the public WebApp URL stays unhealthy for
WEBAPP_URL_MONITOR_FAILURE_SECONDS (default: 3600), the script starts a fresh
Cloudflare quick tunnel to the local WebApp port, writes the new URL into .env,
restarts Gateway, and publishes the refreshed App entry.

Options:
  --once          Run one check. Default.
  --loop          Run forever, sleeping between checks.
  --start         Start loop mode in tmux session tg-webapp-url-monitor.
  --stop          Stop the monitor tmux session.
  --status        Show monitor session, current URL, state, and recent log.
  --dry-run       Print intended rotation actions without changing runtime.
  --force-rotate  Rotate immediately after local health passes.
  --help          Show this help.

Environment:
  WEBAPP_URL_MONITOR_INTERVAL_SECONDS=300
  WEBAPP_URL_MONITOR_FAILURE_SECONDS=3600
  WEBAPP_URL_MONITOR_AUTO_ROTATE=1
  WEBAPP_URL_MONITOR_PUBLIC_TIMEOUT_SECONDS=25
  WEBAPP_URL_MONITOR_LOCAL_TIMEOUT_SECONDS=8
  WEBAPP_URL_MONITOR_NEW_URL_READY_ATTEMPTS=18
  CLOUDFLARED_BIN=/home/zhanxp/.local/bin/cloudflared
EOF
}

log() {
    mkdir -p "$LOG_DIR"
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    exit 1
}

is_positive_integer() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

for value_name in INTERVAL_SECONDS FAILURE_SECONDS PUBLIC_TIMEOUT_SECONDS LOCAL_TIMEOUT_SECONDS NEW_URL_READY_ATTEMPTS; do
    value="${!value_name}"
    if ! is_positive_integer "$value"; then
        die "$value_name must be a positive integer: $value"
    fi
done

while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)
            MODE="once"
            shift
            ;;
        --loop)
            MODE="loop"
            shift
            ;;
        --start)
            MODE="start"
            shift
            ;;
        --stop)
            MODE="stop"
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force-rotate)
            FORCE_ROTATE=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR"

current_url() {
    load_env
    printf '%s' "${TG_WEBAPP_URL:-}"
}

local_port() {
    load_env
    printf '%s' "${WEBAPP_PORT:-3000}"
}

cloudflared_bin() {
    if [[ -n "${CLOUDFLARED_BIN:-}" ]]; then
        printf '%s' "$CLOUDFLARED_BIN"
        return
    fi

    if [[ -x "$HOME/.local/bin/cloudflared" ]]; then
        printf '%s' "$HOME/.local/bin/cloudflared"
        return
    fi

    command -v cloudflared 2>/dev/null || true
}

url_origin() {
    printf '%s' "$1" | sed -E 's#^(https?://[^/]+).*#\1#'
}

check_local_webapp() {
    local port="$1"
    local body_file
    body_file="$(mktemp)"

    if curl -fsS -m "$LOCAL_TIMEOUT_SECONDS" "http://127.0.0.1:$port/health" -o "$body_file" \
        && rg -q '"status"[[:space:]]*:[[:space:]]*"ok"' "$body_file"; then
        rm -f "$body_file"
        return 0
    fi

    rm -f "$body_file"
    return 1
}

check_public_webapp() {
    local url="$1"
    local origin html_file asset_path asset_url
    html_file="$(mktemp)"

    if [[ -z "$url" ]]; then
        rm -f "$html_file"
        return 1
    fi

    if ! curl -fsSL -m "$PUBLIC_TIMEOUT_SECONDS" "$url/" -o "$html_file"; then
        rm -f "$html_file"
        return 1
    fi

    if rg -qi 'Cloudflare|Tunnel not found|origin has been unregistered|error code: 530|<title>.*error|@vite/client|/src/main' "$html_file"; then
        rm -f "$html_file"
        return 1
    fi

    asset_path="$(sed -nE 's#.*src="([^"]*/assets/index-[^"]+\.js)".*#\1#p' "$html_file" | head -n1)"
    if [[ -z "$asset_path" ]]; then
        rm -f "$html_file"
        return 1
    fi

    origin="$(url_origin "$url")"
    asset_url="$origin$asset_path"
    rm -f "$html_file"
    curl -fsSL -m "$PUBLIC_TIMEOUT_SECONDS" "$asset_url" -o /dev/null
}

check_new_public_webapp() {
    local url="$1"
    local attempts="$NEW_URL_READY_ATTEMPTS"

    while [[ "$attempts" -gt 0 ]]; do
        if check_public_webapp "$url"; then
            return 0
        fi

        attempts="$((attempts - 1))"
        if [[ "$attempts" -le 0 ]]; then
            break
        fi
        if ! tmux has-session -t "$TUNNEL_SESSION" 2>/dev/null; then
            log "Tunnel session exited before new URL became healthy: $TUNNEL_SESSION"
            return 1
        fi
        log "Waiting for new WebApp URL to become reachable: $url attempts_left=$attempts"
        sleep 5
    done

    return 1
}

read_state_value() {
    local key="$1"
    if [[ ! -f "$STATE_FILE" ]]; then
        return 0
    fi
    awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$STATE_FILE"
}

write_state() {
    local first_failed_at="$1"
    local url="$2"
    local reason="$3"
    local now
    now="$(date +%s)"
    mkdir -p "$(dirname "$STATE_FILE")"
    {
        printf 'FIRST_FAILED_AT=%s\n' "$first_failed_at"
        printf 'LAST_CHECK_AT=%s\n' "$now"
        printf 'URL=%s\n' "$url"
        printf 'REASON=%s\n' "$reason"
    } > "$STATE_FILE"
}

clear_failure_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
    fi
}

mark_failure_and_get_age() {
    local url="$1"
    local reason="$2"
    local now first_failed_at state_url
    now="$(date +%s)"
    first_failed_at="$(read_state_value FIRST_FAILED_AT)"
    state_url="$(read_state_value URL)"

    if [[ -z "$first_failed_at" || ! "$first_failed_at" =~ ^[0-9]+$ || "$state_url" != "$url" ]]; then
        first_failed_at="$now"
    fi

    write_state "$first_failed_at" "$url" "$reason"
    printf '%s' "$((now - first_failed_at))"
}

update_env_url() {
    local new_url="$1"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "DRY-RUN: would set TG_WEBAPP_URL=$new_url in $ENV_FILE"
        return 0
    fi

    python3 - "$ENV_FILE" "$new_url" <<'PY'
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
new_url = sys.argv[2]
lines = env_path.read_text(encoding='utf-8').splitlines() if env_path.exists() else []
updated = False
out = []
for line in lines:
    if line.startswith('TG_WEBAPP_URL='):
        out.append(f'TG_WEBAPP_URL={new_url}')
        updated = True
    else:
        out.append(line)
if not updated:
    out.append(f'TG_WEBAPP_URL={new_url}')
env_path.write_text('\n'.join(out) + '\n', encoding='utf-8')
PY
}

kill_old_quick_tunnel() {
    local port="$1"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "DRY-RUN: would stop tmux session $TUNNEL_SESSION and cloudflared processes for port $port"
        return 0
    fi

    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    ps -eo pid=,args= \
        | awk -v port="$port" '$0 ~ /[c]loudflared tunnel --url/ && $0 ~ ("http://(127.0.0.1|localhost):" port) {print $1}' \
        | xargs -r kill
    sleep 2
}

start_quick_tunnel() {
    local port="$1"
    local bin command
    bin="$(cloudflared_bin)"
    if [[ -z "$bin" || ! -x "$bin" ]]; then
        die "cloudflared executable not found. Set CLOUDFLARED_BIN."
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "DRY-RUN: would start $bin tunnel --url http://127.0.0.1:$port"
        return 0
    fi

    : > "$TUNNEL_LOG_FILE"
    printf -v command 'cd %q && %q tunnel --url %q --no-autoupdate --protocol http2 --loglevel info 2>&1 | tee -a %q' \
        "$PROJECT_DIR" "$bin" "http://127.0.0.1:$port" "$TUNNEL_LOG_FILE"
    tmux new-session -d -s "$TUNNEL_SESSION" "$command"
}

wait_for_tunnel_url() {
    local new_url=""
    local attempts=60

    while [[ "$attempts" -gt 0 ]]; do
        new_url="$(
            rg -o 'https://[A-Za-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG_FILE" 2>/dev/null \
                | rg -v '^https://api\.trycloudflare\.com$' \
                | tail -n1 || true
        )"
        if [[ -n "$new_url" ]]; then
            printf '%s' "$new_url"
            return 0
        fi
        attempts="$((attempts - 1))"
        sleep 2
    done

    return 1
}

restart_gateway() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "DRY-RUN: would run scripts/restart-gateway.sh"
        return 0
    fi

    bash scripts/restart-gateway.sh
}

rotate_tunnel_and_deploy() {
    local port="$1"
    local old_url="$2"
    local new_url

    log "Rotating WebApp tunnel after sustained URL failure: old_url=$old_url port=$port"
    kill_old_quick_tunnel "$port"
    start_quick_tunnel "$port"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    new_url="$(wait_for_tunnel_url)" || die "new quick tunnel URL was not found in $TUNNEL_LOG_FILE"
    log "New WebApp tunnel URL: $new_url"

    if ! check_new_public_webapp "$new_url"; then
        die "new tunnel URL did not pass public WebApp health check: $new_url"
    fi

    update_env_url "$new_url"
    export TG_WEBAPP_URL="$new_url"

    restart_gateway
    clear_failure_state
    log "WebApp URL rotation completed: $new_url"
}

run_once() {
    local url port age reason
    url="$(current_url)"
    port="$(local_port)"

    if [[ -z "$url" ]]; then
        age="$(mark_failure_and_get_age "" "TG_WEBAPP_URL missing")"
        log "TG_WEBAPP_URL is missing; failure_age=${age}s"
        return 1
    fi

    if ! check_local_webapp "$port"; then
        age="$(mark_failure_and_get_age "$url" "local WebApp health failed")"
        log "Local WebApp health failed on port $port; not rotating public URL; failure_age=${age}s"
        if [[ "$age" -ge "$FAILURE_SECONDS" && "$AUTO_ROTATE" = "1" ]]; then
            log "Local health has failed for threshold; restarting Gateway before any tunnel rotation."
            restart_gateway
        fi
        return 1
    fi

    if [[ "$FORCE_ROTATE" -eq 1 ]]; then
        rotate_tunnel_and_deploy "$port" "$url"
        return 0
    fi

    if check_public_webapp "$url"; then
        clear_failure_state
        log "WebApp URL healthy: $url"
        return 0
    fi

    reason="public WebApp URL failed"
    age="$(mark_failure_and_get_age "$url" "$reason")"
    log "$reason: $url; failure_age=${age}s threshold=${FAILURE_SECONDS}s"

    if [[ "$age" -lt "$FAILURE_SECONDS" ]]; then
        return 1
    fi

    if [[ "$AUTO_ROTATE" != "1" ]]; then
        log "Auto-rotate disabled; leaving URL unchanged."
        return 1
    fi

    rotate_tunnel_and_deploy "$port" "$url"
}

show_status() {
    local url
    url="$(current_url)"
    echo "project=$PROJECT_DIR"
    echo "env_file=$ENV_FILE"
    echo "url=$url"
    echo "monitor_session=$MONITOR_SESSION"
    if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
        echo "monitor=running"
    else
        echo "monitor=stopped"
    fi
    if tmux has-session -t "$TUNNEL_SESSION" 2>/dev/null; then
        echo "tunnel=running"
    else
        echo "tunnel=stopped"
    fi
    if [[ -f "$STATE_FILE" ]]; then
        echo "--- state ---"
        sed -n '1,80p' "$STATE_FILE"
    fi
    if [[ -f "$LOG_FILE" ]]; then
        echo "--- recent log ---"
        tail -n 30 "$LOG_FILE"
    fi
}

start_monitor_session() {
    if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
        log "Monitor already running: $MONITOR_SESSION"
        return 0
    fi

    local command
    printf -v command 'cd %q && bash %q --loop' "$PROJECT_DIR" "$SCRIPT_DIR/monitor-webapp-url.sh"
    tmux new-session -d -s "$MONITOR_SESSION" "$command"
    log "Started WebApp URL monitor tmux session: $MONITOR_SESSION"
}

stop_monitor_session() {
    if tmux kill-session -t "$MONITOR_SESSION" 2>/dev/null; then
        log "Stopped WebApp URL monitor tmux session: $MONITOR_SESSION"
    else
        log "Monitor session not running: $MONITOR_SESSION"
    fi
}

case "$MODE" in
    once)
        run_once
        ;;
    loop)
        log "Starting WebApp URL monitor loop: interval=${INTERVAL_SECONDS}s threshold=${FAILURE_SECONDS}s"
        while true; do
            run_once || true
            sleep "$INTERVAL_SECONDS"
        done
        ;;
    start)
        start_monitor_session
        ;;
    stop)
        stop_monitor_session
        ;;
    status)
        show_status
        ;;
esac
