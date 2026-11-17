#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHDOG_DIR="$ROOT_DIR/scripts/apps/codex/app-server-watchdog"
WATCHDOG="$WATCHDOG_DIR/codex_app_server_watchdog.sh"
WATCHDOG_LIB="$WATCHDOG_DIR/codex_app_server_watchdog_lib.sh"
INSTALLER="$WATCHDOG_DIR/install.sh"
UNIT="$ROOT_DIR/configs/codex/systemd/codex-app-server-watchdog.service"
SYNC="$ROOT_DIR/configs/sync.sh"
TMP_DIR="$(mktemp -d)"
TEST_FAILURES=0
TEST_RESULTS=()
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    builtin kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

for required_file in "$WATCHDOG" "$WATCHDOG_LIB" "$INSTALLER" "$UNIT" "$SYNC"; do
  if [[ ! -f "$required_file" ]]; then
    echo "missing machine-level watchdog asset: $required_file" >&2
    exit 1
  fi
done

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "assertion failed: $message (expected=$expected actual=$actual)" >&2
    return 1
  fi
}

assert_file_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "assertion failed: $message (missing '$needle' in $file)" >&2
    return 1
  fi
}

assert_file_not_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if grep -Fq "$needle" "$file"; then
    echo "assertion failed: $message (unexpected '$needle' in $file)" >&2
    return 1
  fi
}

run_test() {
  local name="$1"
  shift
  if "$@"; then
    TEST_RESULTS+=("PASS $name")
  else
    TEST_RESULTS+=("FAIL $name")
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
}

new_sandbox() {
  local name="$1"
  local sandbox="$TMP_DIR/$name"
  mkdir -p \
    "$sandbox/home/.local/bin" \
    "$sandbox/home/.codex/log" \
    "$sandbox/home/.codex/app-server-control" \
    "$sandbox/home/.codex/packages/standalone/current" \
    "$sandbox/home/.codex/packages/standalone/releases/20260723/bin" \
    "$sandbox/bin" \
    "$sandbox/state"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
    > "$sandbox/home/.codex/packages/standalone/current/codex"
  chmod 700 "$sandbox/home/.codex/packages/standalone/current/codex"
  printf '%s\n' "$sandbox"
}

write_fake_common_tools() {
  local sandbox="$1"

  cat > "$sandbox/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "$sandbox/bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF

  cat > "$sandbox/bin/sleep" <<'EOF'
#!/usr/bin/env bash
arg="${1:-}"
if [[ -n "${CODEX_TEST_SLEEP_LOG:-}" ]]; then
  printf '%s\n' "$arg" >> "$CODEX_TEST_SLEEP_LOG"
fi
if [[ "$arg" == "${CODEX_TEST_MAIN_SLEEP:-}" ]]; then
  count=0
  if [[ -f "${CODEX_TEST_MAIN_SLEEP_COUNT_FILE:-}" ]]; then
    count="$(cat "$CODEX_TEST_MAIN_SLEEP_COUNT_FILE")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$CODEX_TEST_MAIN_SLEEP_COUNT_FILE"
  if (( count >= ${CODEX_TEST_MAX_MAIN_SLEEPS:-9999} )); then
    kill -TERM "$PPID" 2>/dev/null || true
  fi
fi
exit 0
EOF

  cat > "$sandbox/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r pid; do
  [[ -r "/proc/$pid/cmdline" ]] || continue
  if tr '\0' ' ' < "/proc/$pid/cmdline" | grep -Fq "$HOME/.codex/"; then
    printf '%s\n' "$pid"
  fi
done < <(/usr/bin/pgrep "$@" 2>/dev/null || true)
EOF

  chmod 700 "$sandbox/bin/flock" "$sandbox/bin/timeout" "$sandbox/bin/sleep" "$sandbox/bin/pgrep"
}

write_fake_codex() {
  local sandbox="$1"
  cat > "$sandbox/home/.local/bin/codex-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="$*"
printf '%s\n' "$cmd" >> "${CALLS_LOG:?}"

plan_var=""
case "$cmd" in
  "app-server daemon version")
    plan_var="VERSION_PLAN"
    ;;
  "app-server daemon enable-remote-control")
    plan_var="ENABLE_PLAN"
    ;;
  "app-server daemon restart")
    plan_var="RESTART_PLAN"
    ;;
  "app-server daemon bootstrap --remote-control")
    plan_var="BOOTSTRAP_PLAN"
    ;;
  "app-server daemon start")
    plan_var="START_PLAN"
    ;;
  *)
    printf 'unexpected command: %s\n' "$cmd" >&2
    exit 97
    ;;
esac

plan_file="${!plan_var:-}"
if [[ -z "$plan_file" || ! -f "$plan_file" ]]; then
  printf 'missing plan for %s\n' "$cmd" >&2
  exit 98
fi

line="$(head -n 1 "$plan_file")"
tail -n +2 "$plan_file" > "$plan_file.next" || true
if [[ -s "$plan_file.next" ]]; then
  mv "$plan_file.next" "$plan_file"
else
  rm -f "$plan_file.next"
fi

status="${line%%|*}"
output="${line#*|}"
printf '%s' "$output"
exit "$status"
EOF
  chmod 700 "$sandbox/home/.local/bin/codex-bin"
}

write_plan() {
  local file="$1"
  shift
  : > "$file"
  while (($#)); do
    printf '%s\n' "$1" >> "$file"
    shift
  done
}

start_named_process() {
  local name="$1"
  bash -c 'exec -a "$1" sleep 9999 >/dev/null 2>&1' _ "$name" >/dev/null 2>&1 &
  PIDS+=("$!")
  printf '%s\n' "$!"
}

start_socket_server() {
  local socket_path="$1"
  python3 - "$socket_path" <<'EOF' &
import os
import socket
import sys
import time

path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    os.unlink(path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(1)
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass
finally:
    server.close()
EOF
  PIDS+=("$!")
  for _ in $(seq 1 20); do
    [[ -S "$socket_path" ]] && return 0
    sleep 0.1
  done
  echo "failed to create socket: $socket_path" >&2
  return 1
}

run_watchdog_once() {
  local sandbox="$1"
  local status_file="$sandbox/status"
  (
    export HOME="$sandbox/home"
    export PATH="$sandbox/bin:/usr/bin:/bin"
    export CODEX_BIN="$sandbox/home/.local/bin/codex-bin"
    export CALLS_LOG="$sandbox/calls.log"
    export VERSION_PLAN="$sandbox/version.plan"
    export ENABLE_PLAN="$sandbox/enable.plan"
    export RESTART_PLAN="$sandbox/restart.plan"
    export BOOTSTRAP_PLAN="$sandbox/bootstrap.plan"
    export START_PLAN="$sandbox/start.plan"
    export CODEX_WATCHDOG_LOG="$sandbox/watchdog.log"
    export CODEX_WATCHDOG_STATE_DIR="$sandbox/state"
    export CODEX_WATCHDOG_UPDATE_MODE="${CODEX_WATCHDOG_UPDATE_MODE:-manual}"
    bash "$WATCHDOG" --once
  )
  printf '%s\n' "$?" > "$status_file"
}

run_watchdog_loop() {
  local sandbox="$1"
  local status_file="$sandbox/status"
  (
    export HOME="$sandbox/home"
    export PATH="$sandbox/bin:/usr/bin:/bin"
    export CODEX_BIN="$sandbox/home/.local/bin/codex-bin"
    export CALLS_LOG="$sandbox/calls.log"
    export VERSION_PLAN="$sandbox/version.plan"
    export ENABLE_PLAN="$sandbox/enable.plan"
    export RESTART_PLAN="$sandbox/restart.plan"
    export BOOTSTRAP_PLAN="$sandbox/bootstrap.plan"
    export START_PLAN="$sandbox/start.plan"
    export CODEX_WATCHDOG_LOG="$sandbox/watchdog.log"
    export CODEX_WATCHDOG_STATE_DIR="$sandbox/state"
    export CODEX_WATCHDOG_INTERVAL=7
    export CODEX_WATCHDOG_REMOTE_INTERVAL=0
    export CODEX_TEST_MAIN_SLEEP=7
    export CODEX_TEST_MAX_MAIN_SLEEPS=3
    export CODEX_TEST_MAIN_SLEEP_COUNT_FILE="$sandbox/main-sleep-count"
    export CODEX_TEST_SLEEP_LOG="$sandbox/sleep.log"
    export CODEX_WATCHDOG_UPDATE_MODE="${CODEX_WATCHDOG_UPDATE_MODE:-manual}"
    bash "$WATCHDOG" --loop
  )
  printf '%s\n' "$?" > "$status_file"
}

status_of() {
  cat "$1/status"
}

test_version_ok_socket_live_is_hard_protected() {
  local sandbox socket_path remote_pid updater_pid
  sandbox="$(new_sandbox healthy_socket_live)"
  write_fake_common_tools "$sandbox"
  write_fake_codex "$sandbox"
  write_plan "$sandbox/version.plan" \
    '0|{"status":"running","cliVersion":"0.144.6","managedCodexVersion":"0.144.6","appServerVersion":"0.144.6"}'
  write_plan "$sandbox/enable.plan" '99|enable must not run'
  write_plan "$sandbox/restart.plan" '99|restart must not run'
  write_plan "$sandbox/bootstrap.plan" '99|bootstrap must not run'
  write_plan "$sandbox/start.plan" '99|start must not run'
  socket_path="$sandbox/home/.codex/app-server-control/app-server-control.sock"
  start_socket_server "$socket_path"
  start_named_process "$sandbox/home/.codex/packages/standalone/current/codex app-server --remote-control --listen unix://" >/dev/null
  remote_pid="${PIDS[$((${#PIDS[@]} - 1))]}"
  start_named_process "$sandbox/home/.codex/packages/standalone/current/codex app-server daemon pid-update-loop" >/dev/null
  updater_pid="${PIDS[$((${#PIDS[@]} - 1))]}"
  run_watchdog_once "$sandbox"
  assert_eq "0" "$(status_of "$sandbox")" "healthy socket-live run must succeed" &&
    assert_file_contains 'app-server daemon version' "$sandbox/calls.log" "version probe must run" &&
    assert_file_not_contains 'app-server daemon enable-remote-control' "$sandbox/calls.log" "healthy socket-live run must not enable remote control" &&
    assert_file_not_contains 'app-server daemon restart' "$sandbox/calls.log" "healthy socket-live run must not restart" &&
    assert_file_not_contains 'app-server daemon bootstrap --remote-control' "$sandbox/calls.log" "healthy socket-live run must not bootstrap" &&
    assert_file_not_contains 'app-server daemon start' "$sandbox/calls.log" "healthy socket-live run must not start" &&
    builtin kill -0 "$remote_pid" 2>/dev/null &&
    builtin kill -0 "$updater_pid" 2>/dev/null
}

test_socket_down_recovers_only_on_third_failure_with_start_once() {
  local sandbox
  sandbox="$(new_sandbox socket_down_start_once)"
  write_fake_common_tools "$sandbox"
  write_fake_codex "$sandbox"
  write_plan "$sandbox/version.plan" \
    '1|probe-failed-1' \
    '1|probe-failed-2' \
    '1|probe-failed-3'
  write_plan "$sandbox/enable.plan" '99|enable must not run when socket is down'
  write_plan "$sandbox/restart.plan" '99|restart must not run in manual mode'
  write_plan "$sandbox/bootstrap.plan" '99|bootstrap must not run in manual mode'
  write_plan "$sandbox/start.plan" '0|started'
  run_watchdog_loop "$sandbox" || true
  assert_file_not_contains 'app-server daemon enable-remote-control' "$sandbox/calls.log" "socket-down recovery must not enable remote control" &&
    assert_file_not_contains 'app-server daemon restart' "$sandbox/calls.log" "socket-down recovery must not restart" &&
    assert_file_not_contains 'app-server daemon bootstrap --remote-control' "$sandbox/calls.log" "socket-down recovery must not bootstrap" &&
    assert_eq "1" "$(grep -Fc 'app-server daemon start' "$sandbox/calls.log" 2>/dev/null || true)" "manual mode should start exactly once on the third failure"
}

test_remote_missing_socket_live_never_recovers_or_enables() {
  local sandbox socket_path
  sandbox="$(new_sandbox remote_missing_socket_live)"
  write_fake_common_tools "$sandbox"
  write_fake_codex "$sandbox"
  write_plan "$sandbox/version.plan" \
    '1|probe-failed-but-socket-live-1' \
    '1|probe-failed-but-socket-live-2' \
    '1|probe-failed-but-socket-live-3'
  write_plan "$sandbox/enable.plan" '99|enable must not run while socket is live'
  write_plan "$sandbox/restart.plan" '99|restart must not run while socket is live'
  write_plan "$sandbox/bootstrap.plan" '99|bootstrap must not run while socket is live'
  write_plan "$sandbox/start.plan" '99|start must not run while socket is live'
  socket_path="$sandbox/home/.codex/app-server-control/app-server-control.sock"
  start_socket_server "$socket_path"
  run_watchdog_loop "$sandbox" || true
  assert_file_not_contains 'app-server daemon enable-remote-control' "$sandbox/calls.log" "socket-live remote-missing run must not enable remote control" &&
    assert_file_not_contains 'app-server daemon restart' "$sandbox/calls.log" "socket-live remote-missing run must not restart" &&
    assert_file_not_contains 'app-server daemon bootstrap --remote-control' "$sandbox/calls.log" "socket-live remote-missing run must not bootstrap" &&
    assert_file_not_contains 'app-server daemon start' "$sandbox/calls.log" "socket-live remote-missing run must not start"
}

test_release_path_process_is_semantically_managed() {
  local sandbox release_name
  sandbox="$(new_sandbox release_path_match)"
  release_name="$sandbox/home/.codex/packages/standalone/releases/20260723/bin/codex app-server --remote-control --listen unix://"
  # shellcheck source=../scripts/apps/codex/app-server-watchdog/codex_app_server_watchdog_lib.sh
  . "$WATCHDOG_LIB"
  LOG_FILE="$sandbox/watchdog.log"
  HOME="$sandbox/home"
  if ! remote_control_argv_matches \
    "$sandbox/home/.codex/packages/standalone/releases/20260723/bin/codex" \
    app-server --remote-control --listen unix://; then
    echo "release-path remote-control argv must be recognized semantically" >&2
    return 1
  fi
  if remote_control_argv_matches \
    "$sandbox/home/.codex/packages/standalone/releases/20260723/bin/codex" \
    app-server daemon bootstrap --remote-control; then
    echo "daemon bootstrap must not be mistaken for the live remote-control process" >&2
    return 1
  fi
  destructive_cleanup_is_safe() { return 0; }
  sleep() { :; }
  kill() {
    printf '%s\n' "$*" >> "$sandbox/kill.log"
    return 0
  }
  local release_pid
  start_named_process "$release_name" >/dev/null
  release_pid="${PIDS[$((${#PIDS[@]} - 1))]}"
  stop_matching_app_servers
  unset -f destructive_cleanup_is_safe sleep kill
  assert_file_contains "$release_pid" "$sandbox/kill.log" "release-path app-server must be treated as managed for cleanup"
}

test_bootstrap_mode_waits_for_third_confirmed_failure() {
  local sandbox expected_calls
  sandbox="$(new_sandbox bootstrap_mode_threshold)"
  write_fake_common_tools "$sandbox"
  write_fake_codex "$sandbox"
  write_plan "$sandbox/version.plan" \
    '1|probe-failed-1' \
    '1|probe-failed-2' \
    '1|probe-failed-3'
  write_plan "$sandbox/enable.plan" '99|enable must not run'
  write_plan "$sandbox/restart.plan" '99|restart must not run'
  write_plan "$sandbox/bootstrap.plan" '0|bootstrapped'
  write_plan "$sandbox/start.plan" '99|start must not run in bootstrap mode'
  CODEX_WATCHDOG_UPDATE_MODE=bootstrap run_watchdog_loop "$sandbox" || true
  expected_calls=$'app-server daemon version\napp-server daemon version\napp-server daemon version\napp-server daemon bootstrap --remote-control'
  assert_eq "$expected_calls" "$(cat "$sandbox/calls.log")" "bootstrap mode must bootstrap only after the third failed probe"
}

test_manual_mode_accepts_missing_updater_and_unit_declares_it() {
  local sandbox socket_path
  sandbox="$(new_sandbox manual_mode_updater_missing)"
  write_fake_common_tools "$sandbox"
  write_fake_codex "$sandbox"
  write_plan "$sandbox/version.plan" \
    '0|{"status":"running","cliVersion":"0.144.6","managedCodexVersion":"0.144.6","appServerVersion":"0.144.6"}'
  write_plan "$sandbox/enable.plan" '99|enable must not run in manual mode'
  write_plan "$sandbox/restart.plan" '99|restart must not run in manual mode'
  write_plan "$sandbox/bootstrap.plan" '99|bootstrap must not run in manual mode'
  write_plan "$sandbox/start.plan" '99|start must not run in manual mode'
  socket_path="$sandbox/home/.codex/app-server-control/app-server-control.sock"
  start_socket_server "$socket_path"
  start_named_process "$sandbox/home/.codex/packages/standalone/current/codex app-server --remote-control --listen unix://" >/dev/null
  CODEX_WATCHDOG_UPDATE_MODE=manual run_watchdog_once "$sandbox"
  assert_eq "0" "$(status_of "$sandbox")" "manual mode without updater must remain healthy" &&
    assert_file_contains 'healthy remote-control session preserved; auto-update helper is absent' "$sandbox/watchdog.log" "manual mode should preserve the live session when updater is missing" &&
    assert_file_contains 'Environment=CODEX_WATCHDOG_UPDATE_MODE=manual' "$UNIT" "systemd unit must declare manual update mode"
}

test_installer_staging_runtime_parity() {
  local sandbox staged_home fake_bin systemctl_log runtime_dir runtime_unit
  sandbox="$(new_sandbox installer_parity)"
  staged_home="$sandbox/staged-home"
  fake_bin="$sandbox/bin-install"
  systemctl_log="$sandbox/systemctl.log"
  mkdir -p "$staged_home" "$fake_bin"
  cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
EOF
  chmod 700 "$fake_bin/systemctl"
  HOME="$staged_home" PATH="$fake_bin:/usr/bin:/bin" SYSTEMCTL_LOG="$systemctl_log" \
    CODEX_WATCHDOG_INSTALL_ONLY=1 \
    bash "$SYNC" codex-watchdog-install >/dev/null
  runtime_dir="$staged_home/.local/libexec/codex-app-server-watchdog"
  runtime_unit="$staged_home/.config/systemd/user/codex-app-server-watchdog.service"
  cmp -s "$WATCHDOG" "$runtime_dir/codex_app_server_watchdog.sh" &&
    cmp -s "$WATCHDOG_LIB" "$runtime_dir/codex_app_server_watchdog_lib.sh" &&
    cmp -s "$UNIT" "$runtime_unit" &&
    [[ -x "$runtime_dir/codex_app_server_watchdog.sh" ]] &&
    [[ ! -x "$runtime_dir/codex_app_server_watchdog_lib.sh" ]] &&
    [[ ! -s "$systemctl_log" ]] &&
    assert_file_contains 'Environment=CODEX_WATCHDOG_UPDATE_MODE=manual' "$runtime_unit" "staged runtime unit must preserve manual update mode"
}

run_test "version_ok_socket_live_is_hard_protected" test_version_ok_socket_live_is_hard_protected
run_test "socket_down_recovers_only_on_third_failure_with_start_once" test_socket_down_recovers_only_on_third_failure_with_start_once
run_test "remote_missing_socket_live_never_recovers_or_enables" test_remote_missing_socket_live_never_recovers_or_enables
run_test "release_path_process_is_semantically_managed" test_release_path_process_is_semantically_managed
run_test "bootstrap_mode_waits_for_third_confirmed_failure" test_bootstrap_mode_waits_for_third_confirmed_failure
run_test "manual_mode_accepts_missing_updater_and_unit_declares_it" test_manual_mode_accepts_missing_updater_and_unit_declares_it
run_test "installer_staging_runtime_parity" test_installer_staging_runtime_parity

printf '%s\n' "${TEST_RESULTS[@]}"

if ((TEST_FAILURES > 0)); then
  echo "test_codex_app_server_watchdog: FAIL ($TEST_FAILURES failures)" >&2
  exit 1
fi

echo "test_codex_app_server_watchdog: PASS"
