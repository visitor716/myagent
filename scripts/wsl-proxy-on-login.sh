#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${HOME}/.codex/log"
LOG_FILE="${LOG_DIR}/wsl-proxy-on-login.log"
LOCK_FILE="${LOG_DIR}/wsl-proxy-on-login.lock"
ATTEMPTS="${WSL_PROXY_LOGIN_ATTEMPTS:-30}"
DELAY_SECONDS="${WSL_PROXY_LOGIN_DELAY_SECONDS:-10}"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" >>"$LOG_FILE"
}

case "$ATTEMPTS:$DELAY_SECONDS" in
  *[!0-9:]*|:*|*:)
    log "Invalid retry configuration: attempts=$ATTEMPTS delay=$DELAY_SECONDS"
    exit 2
    ;;
esac

if [ ! -f "$HOME/.wsl-proxy.env" ]; then
  log "Missing $HOME/.wsl-proxy.env"
  exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Skipped because another proxy startup check is running"
  exit 0
fi

# shellcheck disable=SC1090
source "$HOME/.wsl-proxy.env"

run_proxy_commands() {
  proxyon && proxycheck
}

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  log "Attempt $attempt/$ATTEMPTS: proxyon && proxycheck"

  if run_proxy_commands 2>&1 \
    | sed -E '/^(set-cookie|report-to|nel):/Id' \
    >>"$LOG_FILE"; then
    log "proxyon && proxycheck succeeded"
    exit 0
  fi

  log "proxyon && proxycheck failed"
  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    sleep "$DELAY_SECONDS"
  fi
  attempt=$((attempt + 1))
done

log "Proxy startup check failed after $ATTEMPTS attempts"
exit 1
