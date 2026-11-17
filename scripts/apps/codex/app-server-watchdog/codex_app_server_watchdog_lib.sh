#!/usr/bin/env bash
# Shared health-check and recovery functions for codex_app_server_watchdog.sh.

usage() {
  cat <<'EOF'
Usage: codex_app_server_watchdog.sh [--once|--loop|--no-remote|--help]

Checks the local Codex app-server daemon and remote-control process state. A
live control socket is a hard continuity boundary. Recovery is allowed only
after the daemon probe and socket are both unavailable for consecutive checks.

Environment:
  CODEX_WATCHDOG_WORKDIR            Working directory for daemon starts.
  CODEX_WATCHDOG_INTERVAL           Loop interval in seconds. Default: 60.
  CODEX_WATCHDOG_REMOTE_INTERVAL    Remote-control process check interval. Default: 60.
  CODEX_WATCHDOG_RESTART_COOLDOWN   Minimum seconds between recovery attempts. Default: 30.
  CODEX_WATCHDOG_FAILURE_THRESHOLD  Confirmed unavailable probes before recovery. Default: 3.
  CODEX_WATCHDOG_UPDATE_MODE        manual (daemon start) or bootstrap. Default: manual.
  CODEX_WATCHDOG_SOCKET_PATH        Override the control socket path for isolated tests.
  CODEX_WATCHDOG_LOG                Log file path.
  CODEX_WATCHDOG_ENV_FILE           Optional env file to source, default ~/.codex/.env.
EOF
}

log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" | tee -a "$LOG_FILE"
}

compact_output() {
  tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-1600
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi

  # The watchdog intentionally bypasses codex-proxy-wrapper. Load the shared
  # WSL proxy helper so a newly started daemon inherits the Windows proxy.
  local proxy_helper="${WSL_PROXY_HELPER:-$HOME/.wsl-proxy.env}"
  if [[ -f "$proxy_helper" ]]; then
    # shellcheck disable=SC1090
    . "$proxy_helper"
    WSL_PROXY_QUIET=1 proxyon 2>/dev/null || true
  fi
}

resolve_codex_bin() {
  local candidate
  if [[ -n "${CODEX_BIN:-}" && -x "${CODEX_BIN:-}" ]]; then
    printf '%s\n' "$CODEX_BIN"
    return 0
  fi

  for candidate in \
    "$HOME/.local/bin/codex-bin" \
    "$HOME/.codex/packages/standalone/current/bin/codex" \
    "$HOME/.codex/packages/standalone/current/codex"
  do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

run_codex() {
  local timeout_seconds="$1"
  shift

  if [[ -d "$WORKDIR" ]]; then
    (cd "$WORKDIR" && timeout "$timeout_seconds" "$CODEX_BIN_RESOLVED" "$@" 2>&1 9>&-)
  else
    timeout "$timeout_seconds" "$CODEX_BIN_RESOLVED" "$@" 2>&1 9>&-
  fi
}

version_json_is_healthy() {
  python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

if data.get("status") != "running":
    sys.exit(2)

sys.exit(0)
'
}

version_json_has_mismatch() {
  python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)

app = data.get("appServerVersion")
expected = data.get("managedCodexVersion") or data.get("cliVersion")
sys.exit(0 if app and expected and app != expected else 1)
'
}

record_confirmed_unavailable_probe() {
  local remote_missing="${1:-1}"
  local threshold="${CODEX_WATCHDOG_FAILURE_THRESHOLD:-3}"

  if [[ ! "$threshold" =~ ^[1-9][0-9]*$ ]]; then
    threshold=3
  fi
  UNAVAILABLE_PROBE_FAILURE_THRESHOLD_EFFECTIVE="$threshold"

  if [[ ! "${UNAVAILABLE_PROBE_FAILURE_COUNT:-}" =~ ^[0-9]+$ ]]; then
    UNAVAILABLE_PROBE_FAILURE_COUNT=0
  fi
  if [[ ! "${REMOTE_CONTROL_MISSING_COUNT:-}" =~ ^[0-9]+$ ]]; then
    REMOTE_CONTROL_MISSING_COUNT=0
  fi

  UNAVAILABLE_PROBE_FAILURE_COUNT=$((UNAVAILABLE_PROBE_FAILURE_COUNT + 1))
  if [[ "$remote_missing" == "1" ]]; then
    REMOTE_CONTROL_MISSING_COUNT=$((REMOTE_CONTROL_MISSING_COUNT + 1))
  else
    REMOTE_CONTROL_MISSING_COUNT=0
  fi

  ((UNAVAILABLE_PROBE_FAILURE_COUNT >= threshold)) || return 1
  if [[ "$remote_missing" == "1" ]]; then
    ((REMOTE_CONTROL_MISSING_COUNT >= threshold)) || return 1
  fi
  return 0
}

reset_unavailable_probe_failures() {
  UNAVAILABLE_PROBE_FAILURE_COUNT=0
  REMOTE_CONTROL_MISSING_COUNT=0
}

# Return 0 for listening, 1 for confirmed unavailable, and 2 when `ss` could
# not provide a trustworthy answer. Unknown state is never safe for recovery.
socket_is_listening() {
  local sock="${SOCKET_PATH:-$HOME/.codex/app-server-control/app-server-control.sock}"
  local listeners

  [[ -S "$sock" ]] || return 1
  if ! listeners="$(ss -lxH 2>/dev/null)"; then
    return 2
  fi
  if grep -Fq -- "$sock" <<<"$listeners"; then
    return 0
  fi
  return 1
}

# A stale socket is a socket inode with a successful `ss` snapshot but no
# listener. Probe errors deliberately do not classify the inode as stale.
socket_is_stale() {
  local sock="${SOCKET_PATH:-$HOME/.codex/app-server-control/app-server-control.sock}"
  local status

  [[ -S "$sock" ]] || return 1
  socket_is_listening
  status=$?
  [[ "$status" == "1" ]]
}

remote_control_argv_matches() {
  local executable="${1:-}" subcommand="${2:-}" arg
  local -a argv=("$@")
  local index has_remote_control=0 has_listen=0

  if [[ "${executable##*/}" == "codex" && "$subcommand" == "app-server" && "${argv[2]:-}" != "daemon" ]]; then
    for ((index = 2; index < ${#argv[@]}; index++)); do
      arg="${argv[$index]}"
      [[ "$arg" == "--remote-control" || "$arg" == --remote-control=* ]] && has_remote_control=1
      [[ "$arg" == "--listen" || "$arg" == --listen=* ]] && has_listen=1
    done
    ((has_remote_control == 1 && has_listen == 1)) && return 0
  fi

  # Support an exec-a test/process marker where the semantic command is held in
  # argv[0]. This still matches arguments, never a particular release path.
  if [[ "$executable" == *"/codex app-server "* && "$executable" != *"/codex app-server daemon "* && "$executable" == *"--remote-control"* && "$executable" == *"--listen"* ]]; then
    return 0
  fi
  return 1
}

pid_update_loop_argv_matches() {
  local executable="${1:-}" subcommand="${2:-}" daemon="${3:-}" action="${4:-}"

  if [[ "${executable##*/}" == "codex" && "$subcommand" == "app-server" && "$daemon" == "daemon" && "$action" == "pid-update-loop" ]]; then
    return 0
  fi
  if [[ "$executable" == *"/codex app-server daemon pid-update-loop"* ]]; then
    return 0
  fi
  return 1
}

process_pid_matches() {
  local pid="$1" matcher="$2"
  local -a argv=()

  [[ -r "/proc/$pid/cmdline" ]] || return 1
  mapfile -d '' -t argv < "/proc/$pid/cmdline"
  ((${#argv[@]})) || return 1
  "$matcher" "${argv[@]}"
}

remote_control_process_is_healthy() {
  local pid

  while IFS= read -r pid; do
    process_pid_matches "$pid" remote_control_argv_matches && return 0
  done < <(pgrep -f 'codex.*app-server' 2>/dev/null || true)
  return 1
}

pid_update_loop_is_running() {
  local pid

  while IFS= read -r pid; do
    process_pid_matches "$pid" pid_update_loop_argv_matches && return 0
  done < <(pgrep -f 'codex.*app-server.*daemon.*pid-update-loop' 2>/dev/null || true)
  return 1
}

# Compatibility helper for older diagnostics. In manual-update mode absence is
# expected; callers should use pid_update_loop_is_running when reporting state.
pid_update_loop_is_healthy() {
  if [[ "${UPDATE_MODE:-manual}" == "manual" ]]; then
    ! pid_update_loop_is_running
  else
    pid_update_loop_is_running
  fi
}

process_topology_is_healthy() {
  remote_control_process_is_healthy && socket_is_listening
}

destructive_cleanup_is_safe() {
  local status

  socket_is_listening
  status=$?
  if ((status == 0)); then
    log WARN "stale-process cleanup deferred: control socket is still listening"
    return 1
  fi
  if ((status != 1)); then
    log WARN "stale-process cleanup deferred: control socket state is unknown"
    return 1
  fi
  return 0
}

managed_app_server_cmdline_is_exact() {
  local pid="$1" cmd

  [[ -r "/proc/$pid/cmdline" ]] || return 1
  cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
  case "$cmd" in
    "$HOME/.codex/packages/standalone/current/codex app-server "*|"$HOME/.codex/packages/standalone/current/bin/codex app-server "*|"$HOME/.codex/packages/standalone/releases/"*"/bin/codex app-server "*|"$HOME/.codex/packages/standalone/releases/"*"/codex app-server "*)
      return 0
      ;;
  esac
  return 1
}

stop_matching_app_servers() {
  local pid alive=()
  local pids=()

  if ! destructive_cleanup_is_safe; then
    return 1
  fi

  while IFS= read -r pid; do
    managed_app_server_cmdline_is_exact "$pid" && pids+=("$pid")
  done < <(pgrep -f 'codex.*app-server' 2>/dev/null || true)

  if ((${#pids[@]} == 0)); then
    log WARN "no matching stale codex app-server processes found"
    return 0
  fi

  log WARN "stopping stale codex app-server pids: ${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true
  sleep 3

  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      alive+=("$pid")
    fi
  done

  if ((${#alive[@]})); then
    log WARN "force-stopping stubborn stale pids: ${alive[*]}"
    kill -KILL "${alive[@]}" 2>/dev/null || true
    sleep 1
  fi
}

recovery_allowed() {
  local now last

  now="$(date +%s)"
  last="$(cat "$LAST_RESTART_FILE" 2>/dev/null || printf '0')"
  if [[ "$last" =~ ^[0-9]+$ ]] && ((now - last < RESTART_COOLDOWN_SECONDS)); then
    log WARN "recovery skipped: cooldown active (${now}-${last}<${RESTART_COOLDOWN_SECONDS})"
    return 1
  fi
  printf '%s\n' "$now" > "$LAST_RESTART_FILE"
  return 0
}

recover_unavailable_daemon() {
  local reason="$1"
  local action output status summary verify_output socket_status
  local sock="${SOCKET_PATH:-$HOME/.codex/app-server-control/app-server-control.sock}"

  if ! destructive_cleanup_is_safe; then
    log WARN "recovery aborted: the control socket is live or its state is unknown"
    return 1
  fi
  recovery_allowed || return 1

  log WARN "recovering unavailable codex app-server: $reason"
  if ! stop_matching_app_servers; then
    log WARN "recovery aborted because stale-process cleanup is unsafe"
    return 1
  fi

  if socket_is_stale; then
    log WARN "removing confirmed stale control socket before recovery"
    rm -f "$sock" 2>/dev/null || true
  fi

  if [[ "${UPDATE_MODE:-manual}" == "bootstrap" ]]; then
    action="bootstrap --remote-control"
    output="$(run_codex 60 app-server daemon bootstrap --remote-control)"
  else
    action="start"
    output="$(run_codex 60 app-server daemon start)"
  fi
  status=$?
  summary="$(printf '%s' "$output" | compact_output)"
  if ((status != 0)); then
    log ERROR "daemon $action recovery failed: $summary"
    return 1
  fi
  log INFO "daemon $action recovery command succeeded: $summary"

  sleep 2
  socket_is_listening
  socket_status=$?
  if ((socket_status != 0)); then
    log ERROR "control socket is still unavailable after daemon $action"
    return 1
  fi

  verify_output="$(run_codex "$COMMAND_TIMEOUT_SECONDS" app-server daemon version)"
  if printf '%s' "$verify_output" | version_json_is_healthy; then
    log INFO "daemon version healthy after $action: $(printf '%s' "$verify_output" | compact_output)"
  else
    log WARN "live control socket preserved although daemon version verification after $action was inconclusive"
  fi
  return 0
}
