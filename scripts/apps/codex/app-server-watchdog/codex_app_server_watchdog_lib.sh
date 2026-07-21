#!/usr/bin/env bash
# Shared health-check and recovery functions for codex_app_server_watchdog.sh.

usage() {
  cat <<'EOF'
Usage: codex_app_server_watchdog.sh [--once|--loop|--no-remote|--help]

Checks the local Codex app-server daemon and remote-control process state. If
the daemon is down, stale, or the remote-control app-server process is missing,
the script restarts the managed app-server with rate limiting. Version changes
are deferred until a natural restart so active sessions are not interrupted.

Environment:
  CODEX_WATCHDOG_WORKDIR            Working directory for daemon starts.
  CODEX_WATCHDOG_INTERVAL           Loop interval in seconds. Default: 60.
  CODEX_WATCHDOG_REMOTE_INTERVAL    Remote-control process check interval. Default: 60.
  CODEX_WATCHDOG_RESTART_COOLDOWN   Minimum seconds between restarts. Default: 120.
  CODEX_WATCHDOG_FAILURE_THRESHOLD  Consecutive failed probes before restarting a live socket. Default: 3.
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

defer_daemon_restart_after_probe_failure() {
  local threshold="${CODEX_WATCHDOG_FAILURE_THRESHOLD:-3}"

  if [[ ! "$threshold" =~ ^[1-9][0-9]*$ ]]; then
    threshold=3
  fi
  DAEMON_PROBE_FAILURE_THRESHOLD_EFFECTIVE="$threshold"

  if [[ ! "${DAEMON_PROBE_FAILURE_COUNT:-}" =~ ^[0-9]+$ ]]; then
    DAEMON_PROBE_FAILURE_COUNT=0
  fi
  DAEMON_PROBE_FAILURE_COUNT=$((DAEMON_PROBE_FAILURE_COUNT + 1))

  process_topology_is_healthy || return 1
  ((DAEMON_PROBE_FAILURE_COUNT < threshold))
}

reset_daemon_probe_failures() {
  DAEMON_PROBE_FAILURE_COUNT=0
}

# Check if any running app-server process is orphaned.
# A listening control socket is sufficient evidence of an owned, usable
# service. The pid-update-loop may be absent after restart or WSL recovery; that
# degrades automatic updates but must not classify the active session as orphan.
any_app_server_process_is_orphan() {
  local app_pids=()
  local pid

  while IFS= read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    app_pids+=("$pid")
  done < <(pgrep -f 'codex app-server( |$)' 2>/dev/null || true)

  # No app-server processes at all = not orphaned, just absent
  ((${#app_pids[@]})) || return 1

  socket_is_listening && return 1
  return 0
}

# Check if the socket file is stale (exists but no process is listening).
# WSL unclean shutdowns can leave behind a socket file with no server.
socket_is_stale() {
  local sock="$HOME/.codex/app-server-control/app-server-control.sock"
  [[ -S "$sock" ]] || return 1          # no socket = not stale
  ss -lx 2>/dev/null | grep -qF "$sock" && return 1  # socket is listening = not stale
  return 0  # socket file exists but nothing is listening = stale
}

socket_is_listening() {
  local sock="$HOME/.codex/app-server-control/app-server-control.sock"
  [[ -S "$sock" ]] || return 1
  ss -lx 2>/dev/null | grep -qF "$sock"
}

destructive_cleanup_is_safe() {
  if socket_is_listening; then
    log WARN "stale-process cleanup deferred: control socket is still listening"
    return 1
  fi
  return 0
}

restart_allowed() {
  local now last
  now="$(date +%s)"
  last="$(cat "$LAST_RESTART_FILE" 2>/dev/null || printf '0')"

  if [[ "$last" =~ ^[0-9]+$ ]] && ((now - last < RESTART_COOLDOWN_SECONDS)); then
    # Always bypass cooldown if no app-server processes exist (fresh start / crash)
    if ! pgrep -f '^/home/zhanxp/.codex/packages/standalone/current/codex app-server( |$)' >/dev/null 2>&1; then
      log WARN "restart cooldown bypassed: no codex app-server processes are running"
      printf '%s\n' "$now" > "$LAST_RESTART_FILE"
      return 0
    fi

    # Bypass cooldown if orphan processes detected (WSL unclean shutdown scenario)
    if any_app_server_process_is_orphan; then
      log WARN "restart cooldown bypassed: orphan app-server processes detected"
      printf '%s\n' "$now" > "$LAST_RESTART_FILE"
      return 0
    fi

    # Bypass cooldown if socket is stale (leftover from killed VM)
    if socket_is_stale; then
      log WARN "restart cooldown bypassed: stale socket file detected"
      printf '%s\n' "$now" > "$LAST_RESTART_FILE"
      return 0
    fi

    log WARN "restart skipped: cooldown active (${now}-${last}<${RESTART_COOLDOWN_SECONDS})"
    return 1
  fi

  printf '%s\n' "$now" > "$LAST_RESTART_FILE"
  return 0
}

remote_control_process_is_healthy() {
  local pid cmd

  while IFS= read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    case "$cmd" in
      "$MANAGED_CODEX_APP app-server "*--remote-control*)
        return 0
        ;;
    esac
  done < <(pgrep -f 'codex app-server' || true)

  return 1
}

pid_update_loop_is_healthy() {
  local pid cmd

  while IFS= read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    case "$cmd" in
      "$MANAGED_CODEX_APP app-server daemon pid-update-loop "*|"$MANAGED_CODEX_APP app-server daemon pid-update-loop")
        return 0
        ;;
    esac
  done < <(pgrep -f 'codex app-server daemon pid-update-loop' || true)

  return 1
}

process_topology_is_healthy() {
  remote_control_process_is_healthy && socket_is_listening
}

ensure_remote_control_enabled() {
  local output status

  if process_topology_is_healthy; then
    return 0
  fi

  output="$(run_codex 60 app-server daemon enable-remote-control)"
  status=$?
  if ((status != 0)); then
    log WARN "enable-remote-control failed: $(printf '%s' "$output" | compact_output)"
    return 1
  fi

  log INFO "enable-remote-control ok: $(printf '%s' "$output" | compact_output)"
  sleep 1
  process_topology_is_healthy
}

stop_matching_app_servers() {
  local pid cmd alive=()
  local pids=()

  if ! destructive_cleanup_is_safe; then
    return 1
  fi

  while IFS= read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    case "$cmd" in
      "$MANAGED_CODEX_APP app-server "*|"$HOME/.codex/packages/standalone/releases/"*"/codex app-server "*)
        pids+=("$pid")
        ;;
    esac
  done < <(pgrep -f 'codex app-server' || true)

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

restart_daemon() {
  local reason="$1"
  local output status summary enable_output enable_status verify_output
  local restart_ok=0
  local initial_action="restart"

  if ! restart_allowed; then
    return 1
  fi

  log WARN "restarting codex app-server: $reason"

  # If socket is stale, clean it before attempting restart
  if socket_is_stale; then
    log WARN "removing stale socket before restart"
    rm -f "$HOME/.codex/app-server-control/app-server-control.sock" 2>/dev/null || true
  fi

  if socket_is_listening; then
    output="$(run_codex 60 app-server daemon restart)"
  else
    initial_action="bootstrap"
    log INFO "no live control socket; using durable bootstrap for recovery"
    if ! stop_matching_app_servers; then
      log WARN "bootstrap deferred because stale-process cleanup is unsafe"
      return 1
    fi
    output="$(run_codex 60 app-server daemon bootstrap --remote-control)"
  fi
  status=$?
  summary="$(printf '%s' "$output" | compact_output)"

  # daemon restart can fail because:
  #   (a) old process is "not managed by daemon" → need bootstrap
  #   (b) socket unreachable (WSL crash leftover) → need bootstrap
  #   (c) other transient errors → retry with bootstrap
  if [[ "$initial_action" == "bootstrap" ]] && ((status != 0)); then
    log ERROR "bootstrap failed: $summary"
    return 1
  elif ((status != 0)) || [[ "$output" == *"not managed by codex app-server daemon"* ]]; then
    log WARN "daemon restart failed or reported unmanaged; attempting bootstrap"
    if ! stop_matching_app_servers; then
      log WARN "bootstrap deferred to preserve the listening app-server session"
      return 1
    fi
    output="$(run_codex 60 app-server daemon bootstrap --remote-control)"
    status=$?
    summary="$(printf '%s' "$output" | compact_output)"
  fi

  if ((status != 0)); then
    log ERROR "restart/bootstrap failed: $summary"
    return 1
  fi

  log INFO "restart/bootstrap ok: $summary"
  restart_ok=1

  enable_output="$(run_codex 60 app-server daemon enable-remote-control)"
  enable_status=$?
  if ((enable_status != 0)); then
    log WARN "enable-remote-control failed (will retry): $(printf '%s' "$enable_output" | compact_output)"
  else
    log INFO "enable-remote-control ok: $(printf '%s' "$enable_output" | compact_output)"
  fi

  sleep 2

  verify_output="$(run_codex "$COMMAND_TIMEOUT_SECONDS" app-server daemon version)"
  if printf '%s' "$verify_output" | version_json_is_healthy; then
    log INFO "daemon version healthy after restart: $(printf '%s' "$verify_output" | compact_output)"
  else
    log ERROR "daemon version still unhealthy after restart: $(printf '%s' "$verify_output" | compact_output)"
    return 1
  fi

  if process_topology_is_healthy; then
    log INFO "codex app-server process topology healthy after restart"
    return 0
  fi

  # Topology incomplete after daemon restart — try bootstrap as fallback
  # This handles the common case where daemon restart creates orphan processes
  log WARN "topology incomplete after daemon restart; trying bootstrap fallback"
  if ! stop_matching_app_servers; then
    log WARN "bootstrap fallback deferred to preserve the listening app-server session"
    return 1
  fi
  output="$(run_codex 60 app-server daemon bootstrap --remote-control)"
  status=$?
  summary="$(printf '%s' "$output" | compact_output)"

  if ((status != 0)); then
    log ERROR "bootstrap fallback failed: $summary"
    return 1
  fi
  log INFO "bootstrap fallback ok: $summary"

  enable_output="$(run_codex 60 app-server daemon enable-remote-control)"
  enable_status=$?
  if ((enable_status != 0)); then
    log WARN "enable-remote-control after bootstrap failed: $(printf '%s' "$enable_output" | compact_output)"
  else
    log INFO "enable-remote-control after bootstrap ok: $(printf '%s' "$enable_output" | compact_output)"
  fi

  sleep 2

  verify_output="$(run_codex "$COMMAND_TIMEOUT_SECONDS" app-server daemon version)"
  if printf '%s' "$verify_output" | version_json_is_healthy; then
    log INFO "daemon version healthy after bootstrap: $(printf '%s' "$verify_output" | compact_output)"
  else
    log ERROR "daemon version still unhealthy after bootstrap: $(printf '%s' "$verify_output" | compact_output)"
    return 1
  fi

  if process_topology_is_healthy; then
    log INFO "codex app-server process topology healthy after bootstrap"
    return 0
  fi

  log ERROR "codex app-server process topology incomplete after bootstrap"
  return 1
}
