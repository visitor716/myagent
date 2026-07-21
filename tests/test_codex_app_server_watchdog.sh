#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHDOG_DIR="$ROOT_DIR/scripts/apps/codex/app-server-watchdog"
WATCHDOG="$WATCHDOG_DIR/codex_app_server_watchdog.sh"
WATCHDOG_LIB="$WATCHDOG_DIR/codex_app_server_watchdog_lib.sh"
UNIT="$ROOT_DIR/configs/codex/systemd/codex-app-server-watchdog.service"
SYNC="$ROOT_DIR/configs/sync.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for required_file in "$WATCHDOG" "$WATCHDOG_LIB" "$UNIT" "$SYNC"; do
    if [[ ! -f "$required_file" ]]; then
        echo "missing machine-level watchdog asset: $required_file" >&2
        exit 1
    fi
done

LOG_FILE="$TMP_DIR/watchdog.log"
HOME="${HOME:-/home/zhanxp}"
MANAGED_CODEX_APP="$HOME/.codex/packages/standalone/current/codex"

# shellcheck source=../scripts/apps/codex/app-server-watchdog/codex_app_server_watchdog_lib.sh
. "$WATCHDOG_LIB"

matching_versions='{"status":"running","cliVersion":"0.144.6","managedCodexVersion":"0.144.6","appServerVersion":"0.144.6"}'
mismatched_versions='{"status":"running","cliVersion":"0.144.6","managedCodexVersion":"0.144.6","appServerVersion":"0.144.5"}'
stopped_daemon='{"status":"stopped","cliVersion":"0.144.6","managedCodexVersion":"0.144.6","appServerVersion":"0.144.6"}'

printf '%s' "$matching_versions" | version_json_is_healthy
printf '%s' "$mismatched_versions" | version_json_is_healthy
if printf '%s' "$stopped_daemon" | version_json_is_healthy; then
    echo "stopped daemon must remain unhealthy" >&2
    exit 1
fi

remote_control_process_is_healthy() { return 0; }
socket_is_listening() { return 0; }
pid_update_loop_is_healthy() { return 1; }
process_topology_is_healthy

socket_is_listening() { return 1; }
if process_topology_is_healthy; then
    echo "remote control without a listening socket must remain unhealthy" >&2
    exit 1
fi

socket_is_listening() { return 0; }
if destructive_cleanup_is_safe; then
    echo "a listening socket must protect the active app-server" >&2
    exit 1
fi

socket_is_listening() { return 1; }
destructive_cleanup_is_safe

CODEX_WATCHDOG_FAILURE_THRESHOLD=3
DAEMON_PROBE_FAILURE_COUNT=0
process_topology_is_healthy() { return 0; }

defer_daemon_restart_after_probe_failure
defer_daemon_restart_after_probe_failure
[[ "$DAEMON_PROBE_FAILURE_COUNT" == "2" ]]
if defer_daemon_restart_after_probe_failure; then
    echo "the third consecutive probe failure must permit recovery" >&2
    exit 1
fi

reset_daemon_probe_failures
[[ "$DAEMON_PROBE_FAILURE_COUNT" == "0" ]]
process_topology_is_healthy() { return 1; }
if defer_daemon_restart_after_probe_failure; then
    echo "missing process/socket topology must recover immediately" >&2
    exit 1
fi

grep -Fxq 'KillMode=process' "$UNIT"
grep -Fxq 'WorkingDirectory=%h' "$UNIT"
grep -Fxq 'Environment=CODEX_WATCHDOG_WORKDIR=%h' "$UNIT"
grep -Fxq 'Environment=CODEX_WATCHDOG_FAILURE_THRESHOLD=3' "$UNIT"
grep -Fxq 'Environment=CODEX_BIN=%h/.local/bin/codex-bin' "$UNIT"
grep -Fxq 'ExecStart=%h/.local/libexec/codex-app-server-watchdog/codex_app_server_watchdog.sh --loop' "$UNIT"
grep -Eq 'sleep "\$INTERVAL_SECONDS".*9>&-' "$WATCHDOG"

if grep -R -Fq '/home/zhanxp/projects/oa-fill-assistant' \
    "$WATCHDOG_DIR" "$UNIT" "$SYNC"; then
    echo "machine-level watchdog assets must not reference oa-fill-assistant" >&2
    exit 1
fi

STAGED_HOME="$TMP_DIR/home"
HOME="$STAGED_HOME" CODEX_WATCHDOG_INSTALL_ONLY=1 \
    bash "$SYNC" codex-watchdog-install >/dev/null

RUNTIME_DIR="$STAGED_HOME/.local/libexec/codex-app-server-watchdog"
RUNTIME_UNIT="$STAGED_HOME/.config/systemd/user/codex-app-server-watchdog.service"
cmp -s "$WATCHDOG" "$RUNTIME_DIR/codex_app_server_watchdog.sh"
cmp -s "$WATCHDOG_LIB" "$RUNTIME_DIR/codex_app_server_watchdog_lib.sh"
cmp -s "$UNIT" "$RUNTIME_UNIT"
[[ -x "$RUNTIME_DIR/codex_app_server_watchdog.sh" ]]
[[ -x "$RUNTIME_DIR/codex_app_server_watchdog_lib.sh" ]]
grep -Fq 'systemctl --user reenable codex-app-server-watchdog.service' "$SYNC"
bash "$SYNC" help | grep -Fq 'codex-watchdog-install'

echo "test_codex_app_server_watchdog: PASS"
