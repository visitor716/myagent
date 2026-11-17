# Codex app-server watchdog manual-update TDD evidence

## Incident and user journey

This change follows the 2026-07-22 incident where the official
`pid-update-loop` replaced app-server during an update and the watchdog treated
the release handoff as a second failure. The watchdog then restarted, killed,
and bootstrapped the backend again, which reset live WebSocket sessions without
a closing handshake.

As a Codex remote-control user, I want a serving control socket to be an
absolute no-mutation boundary, so that updater handoffs and transient process
markers cannot make the watchdog disconnect an active session.

As the machine operator, I want recovery only after three confirmed unavailable
probes and want the deployed service to use manual updates, so that routine
recovery never recreates the hourly updater.

## RED and GREEN report

The first RED run used the old production implementation:

```text
restarting codex app-server: daemon version unhealthy after 1 consecutive failure(s)
no live control socket; using durable bootstrap for recovery
FAIL socket_down_recovers_only_on_third_failure_with_start_once
enable-remote-control failed: enable must not run while socket is live
FAIL remote_missing_socket_live_never_recovers_or_enables
test_codex_app_server_watchdog: FAIL (4 failures)
```

An independent review later found that `daemon bootstrap --remote-control`
could be mistaken for the live service process. A second focused RED run failed
with:

```text
daemon bootstrap must not be mistaken for the live remote-control process
FAIL release_path_process_is_semantically_managed
```

The final GREEN run was:

```text
PASS version_ok_socket_live_is_hard_protected
PASS socket_down_recovers_only_on_third_failure_with_start_once
PASS remote_missing_socket_live_never_recovers_or_enables
PASS release_path_process_is_semantically_managed
PASS bootstrap_mode_waits_for_third_confirmed_failure
PASS manual_mode_accepts_missing_updater_and_unit_declares_it
PASS installer_staging_runtime_parity
test_codex_app_server_watchdog: PASS
```

Checkpoint commits were intentionally not created because `myagent` already
contained unrelated operator changes and this task did not authorize changing
their Git delivery state. This evidence file preserves the RED/GREEN record
without staging or committing unrelated work.

## Test specification

| Guarantee | Test or command | Result |
| --- | --- | --- |
| Healthy daemon version plus live socket invokes no enable, start, restart, kill, or bootstrap path | `version_ok_socket_live_is_hard_protected` | PASS |
| Even three failed version probes cannot mutate the daemon while the socket is listening | `remote_missing_socket_live_never_recovers_or_enables` | PASS |
| Confirmed socket-down probes one and two only increment counters; probe three invokes exactly one `daemon start` in manual mode | `socket_down_recovers_only_on_third_failure_with_start_once` | PASS |
| A release `.../bin/codex app-server --remote-control --listen ...` process is recognized without requiring the `current/codex` path | `release_path_process_is_semantically_managed` | PASS |
| `daemon bootstrap --remote-control` is not misclassified as the serving remote-control process | `release_path_process_is_semantically_managed` negative assertion | PASS |
| Bootstrap remains explicit opt-in and cannot run before the third confirmed failure | `bootstrap_mode_waits_for_third_confirmed_failure` | PASS |
| The deployed unit defaults to manual updates and accepts an absent updater as healthy | `manual_mode_accepts_missing_updater_and_unit_declares_it` | PASS |
| Staged installer output is byte-identical to canonical source and unit files | `installer_staging_runtime_parity` | PASS |

## Verification commands

- `bash -n` on the watchdog, library, installer, sync entrypoint, and focused
  test.
- `bash tests/test_codex_app_server_watchdog.sh`.
- `bash tests/test_sync_mcp_guard.sh`.
- `systemd-analyze --user verify configs/codex/systemd/codex-app-server-watchdog.service`.
- `bash configs/sync.sh validate`.
- `git diff --check --` on the watchdog-scoped files.
- `CODEX_WATCHDOG_INSTALL_ONLY=1 bash configs/sync.sh codex-watchdog-install`
  followed by three source/runtime `cmp` checks.

All listed checks passed. ShellCheck was not available on this machine.

## Live continuity evidence

Before deployment at `2026-07-23T14:58:01+08:00`:

- app-server PID: `30637`
- control socket filesystem inode: `29984`
- socket listener inode reported by `ss`: `82186`
- updater PID: `30663`
- watchdog PID: `413`
- daemon, CLI, and managed Codex version: `0.145.0`

Runtime files were installed offline first. Only the watchdog service was then
restarted with `KillMode=process`. The app-server PID and both socket inode
values stayed unchanged. The updater PID was verified by executable and exact
argv (`app-server daemon pid-update-loop`) before receiving `SIGTERM`.

After deployment:

- app-server PID remained `30637`
- control socket filesystem inode remained `29984`
- `ss` listener inode remained `82186`
- `pid-update-loop` was absent
- watchdog was `active/running`, `NRestarts=0`, `KillMode=process`, and loaded
  `CODEX_WATCHDOG_UPDATE_MODE=manual`
- `codex app-server daemon version` still reported all versions at `0.145.0`
- consecutive live watchdog cycles logged
  `auto-update helper is absent as expected in manual-update mode`
- no new watchdog restart, bootstrap, stale cleanup, transport reset, or
  closing-handshake error appeared after the deployment baseline

## Coverage and known gaps

The shell harness injects all destructive decisions into isolated fake HOME,
PATH, socket, process, and Codex command surfaces. A real app-server outage or
real updater-driven replacement was not forced because doing so would violate
the session-continuity requirement being tested. The failure mechanism is
instead covered by exact command-log assertions plus the live PID/socket
continuity check.

Manual mode deliberately does not kill updater processes during a healthy
watchdog probe. The one existing helper was retired as an explicit maintenance
step during this migration. Future updates must be performed in a maintenance
window; running `daemon bootstrap` again explicitly opts back into durable
updater behavior until that helper is retired again.
