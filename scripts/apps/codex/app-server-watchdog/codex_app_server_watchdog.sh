#!/usr/bin/env bash
set -uo pipefail

DEFAULT_WORKDIR="${HOME:-/home/zhanxp}"
WORKDIR="${CODEX_WATCHDOG_WORKDIR:-$DEFAULT_WORKDIR}"
INTERVAL_SECONDS="${CODEX_WATCHDOG_INTERVAL:-60}"
REMOTE_INTERVAL_SECONDS="${CODEX_WATCHDOG_REMOTE_INTERVAL:-60}"
RESTART_COOLDOWN_SECONDS="${CODEX_WATCHDOG_RESTART_COOLDOWN:-30}"
COMMAND_TIMEOUT_SECONDS="${CODEX_WATCHDOG_TIMEOUT:-30}"
UPDATE_MODE="${CODEX_WATCHDOG_UPDATE_MODE:-manual}"
UNAVAILABLE_PROBE_FAILURE_COUNT=0
REMOTE_CONTROL_MISSING_COUNT=0
ENV_FILE="${CODEX_WATCHDOG_ENV_FILE:-$HOME/.codex/.env}"
LOG_FILE="${CODEX_WATCHDOG_LOG:-$HOME/.codex/log/codex-app-server-watchdog.log}"
STATE_DIR="${CODEX_WATCHDOG_STATE_DIR:-$HOME/.local/state/codex-app-server-watchdog}"
LAST_RESTART_FILE="$STATE_DIR/last-restart"
LOCK_FILE="$STATE_DIR/watchdog.lock"
SOCKET_PATH="${CODEX_WATCHDOG_SOCKET_PATH:-$HOME/.codex/app-server-control/app-server-control.sock}"


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

if [[ "$UPDATE_MODE" != "manual" && "$UPDATE_MODE" != "bootstrap" ]]; then
  log WARN "invalid update mode '$UPDATE_MODE'; falling back to manual"
  UPDATE_MODE="manual"
fi

check_once() {
  local output status summary socket_status version_ok=0 remote_missing=0

  load_env

  if ! CODEX_BIN_RESOLVED="$(resolve_codex_bin)"; then
    log ERROR "codex executable not found"
    return 1
  fi

  output="$(run_codex "$COMMAND_TIMEOUT_SECONDS" app-server daemon version)"
  status=$?
  summary="$(printf '%s' "$output" | compact_output)"

  if ((status == 0)) && printf '%s' "$output" | version_json_is_healthy; then
    version_ok=1
  fi

  socket_is_listening
  socket_status=$?

  # A listening socket is the primary continuity boundary. Never mutate a
  # serving daemon because process markers or version probes can be transient
  # during an official release handoff.
  if ((socket_status == 0)); then
    reset_unavailable_probe_failures

    if ((version_ok)); then
      if printf '%s' "$output" | version_json_has_mismatch; then
        log WARN "version change deferred until the next maintenance restart: $summary"
      fi
    else
      log WARN "serving-degraded: daemon version probe failed (status=$status, output=${summary:-<empty>}); live control socket is hard-protected"
    fi

    if [[ "$CHECK_REMOTE" != "1" ]]; then
      log INFO "healthy: live control socket is protected"
      return 0
    fi

    if ! remote_control_process_is_healthy; then
      log WARN "serving-degraded: remote-control process marker is missing; live control socket is hard-protected"
      return 0
    fi

    if [[ "$UPDATE_MODE" == "manual" ]]; then
      if pid_update_loop_is_running; then
        log WARN "healthy remote-control session preserved; auto-update helper is present but manual-update mode will not stop it while the socket is live"
      else
        log INFO "healthy remote-control session preserved; auto-update helper is absent as expected in manual-update mode"
      fi
    elif pid_update_loop_is_running; then
      log INFO "healthy: daemon version ok, remote-control socket active, and auto-update helper present"
    else
      log WARN "healthy remote-control session preserved; auto-update helper is absent"
    fi
    return 0
  fi

  # A successful daemon-version exchange proves the socket served this probe,
  # even if the subsequent `ss` snapshot raced with a process handoff. Preserve
  # the session for this cycle and require fresh confirmed failures later.
  if ((version_ok)); then
    reset_unavailable_probe_failures
    log WARN "daemon version succeeded while the socket listener snapshot was unavailable; recovery is hard-deferred: $summary"
    return 0
  fi

  # Status 2 means the socket probe itself was inconclusive (for example `ss`
  # failed). Unknown is never permission to clean up or start another daemon.
  if ((socket_status != 1)); then
    reset_unavailable_probe_failures
    log WARN "socket listener probe was inconclusive; recovery is hard-deferred"
    return 0
  fi

  remote_control_process_is_healthy || remote_missing=1
  if ! record_confirmed_unavailable_probe "$remote_missing"; then
    log WARN "daemon unavailable; recovery deferred (${UNAVAILABLE_PROBE_FAILURE_COUNT}/${UNAVAILABLE_PROBE_FAILURE_THRESHOLD_EFFECTIVE}, remote_missing=${REMOTE_CONTROL_MISSING_COUNT}/${UNAVAILABLE_PROBE_FAILURE_THRESHOLD_EFFECTIVE}): status=$status, output=${summary:-<empty>}"
    return 0
  fi

  recover_unavailable_daemon "daemon version failed and control socket was unavailable for ${UNAVAILABLE_PROBE_FAILURE_COUNT} consecutive probes"
  status=$?
  ((status == 0)) && reset_unavailable_probe_failures
  return "$status"
}

if [[ "$MODE" == "once" ]]; then
  check_once
  exit $?
fi

log INFO "watchdog started: workdir=$WORKDIR interval=${INTERVAL_SECONDS}s remote_interval=${REMOTE_INTERVAL_SECONDS}s update_mode=$UPDATE_MODE"
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
