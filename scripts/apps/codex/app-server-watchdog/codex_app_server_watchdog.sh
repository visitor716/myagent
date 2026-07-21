#!/usr/bin/env bash
set -uo pipefail

DEFAULT_WORKDIR="${HOME:-/home/zhanxp}"
WORKDIR="${CODEX_WATCHDOG_WORKDIR:-$DEFAULT_WORKDIR}"
INTERVAL_SECONDS="${CODEX_WATCHDOG_INTERVAL:-60}"
REMOTE_INTERVAL_SECONDS="${CODEX_WATCHDOG_REMOTE_INTERVAL:-60}"
RESTART_COOLDOWN_SECONDS="${CODEX_WATCHDOG_RESTART_COOLDOWN:-30}"
COMMAND_TIMEOUT_SECONDS="${CODEX_WATCHDOG_TIMEOUT:-30}"
DAEMON_PROBE_FAILURE_COUNT=0
ENV_FILE="${CODEX_WATCHDOG_ENV_FILE:-$HOME/.codex/.env}"
LOG_FILE="${CODEX_WATCHDOG_LOG:-$HOME/.codex/log/codex-app-server-watchdog.log}"
STATE_DIR="${CODEX_WATCHDOG_STATE_DIR:-$HOME/.local/state/codex-app-server-watchdog}"
LAST_RESTART_FILE="$STATE_DIR/last-restart"
LOCK_FILE="$STATE_DIR/watchdog.lock"
MANAGED_CODEX_APP="$HOME/.codex/packages/standalone/current/codex"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=codex_app_server_watchdog_lib.sh
. "$SCRIPT_DIR/codex_app_server_watchdog_lib.sh"

MODE="loop"
CHECK_REMOTE="1"
while (($#)); do
  case "$1" in
    --once)
      MODE="once"
      ;;
    --loop)
      MODE="loop"
      ;;
    --no-remote)
      CHECK_REMOTE="0"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  printf '%s [INFO] another watchdog instance is already running\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  exit 0
fi

check_once() {
  local output status summary

  load_env

  if ! CODEX_BIN_RESOLVED="$(resolve_codex_bin)"; then
    log ERROR "codex executable not found"
    return 1
  fi

  output="$(run_codex "$COMMAND_TIMEOUT_SECONDS" app-server daemon version)"
  status=$?
  summary="$(printf '%s' "$output" | compact_output)"

  if ((status != 0)) || ! printf '%s' "$output" | version_json_is_healthy; then
    if defer_daemon_restart_after_probe_failure; then
      log WARN "daemon version probe failed (status=$status, output=${summary:-<empty>}); preserving the active socket (${DAEMON_PROBE_FAILURE_COUNT}/${DAEMON_PROBE_FAILURE_THRESHOLD_EFFECTIVE})"
      return 0
    fi

    restart_daemon "daemon version unhealthy after ${DAEMON_PROBE_FAILURE_COUNT} consecutive failure(s): status=$status, output=${summary:-<empty>}"
    status=$?
    ((status == 0)) && reset_daemon_probe_failures
    return "$status"
  fi

  reset_daemon_probe_failures

  if printf '%s' "$output" | version_json_has_mismatch; then
    log WARN "version change deferred until the next natural app-server restart: $summary"
  fi

  if [[ "$CHECK_REMOTE" == "1" ]]; then
    if ! ensure_remote_control_enabled; then
      restart_daemon "remote-control process missing or enable failed"
      return $?
    fi

    if pid_update_loop_is_healthy; then
      log INFO "healthy: daemon version ok, remote-control socket active, and auto-update helper present"
    else
      log WARN "healthy remote-control session preserved; auto-update helper is absent and will recover on a safe bootstrap"
    fi
  else
    log INFO "healthy: daemon version ok"
  fi
}

if [[ "$MODE" == "once" ]]; then
  check_once
  exit $?
fi

log INFO "watchdog started: workdir=$WORKDIR interval=${INTERVAL_SECONDS}s remote_interval=${REMOTE_INTERVAL_SECONDS}s"
next_remote_probe=0
while true; do
  now="$(date +%s)"
  if ((now >= next_remote_probe)); then
    CHECK_REMOTE="1"
    next_remote_probe=$((now + REMOTE_INTERVAL_SECONDS))
  else
    CHECK_REMOTE="0"
  fi

  check_once || true
  sleep "$INTERVAL_SECONDS" 9>&-
done
