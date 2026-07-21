# Codex app-server watchdog runtime migration TDD evidence

## Source and user journey

This migration was derived from the 2026-07-21 incident where the machine-level
Codex watchdog was running directly from a dirty `oa-fill-assistant` worktree.
No external plan file was used.

As a Codex user, I want app-server recovery to run from stable user-level
runtime files so that deleting, switching, or editing an application repository
cannot change the machine watchdog.

## Migration plan

1. Lock the existing continuity behavior and project-independence boundary with
   a failing shell regression.
2. Store the canonical source under `myagent/scripts/apps/codex/` and use a
   neutral `%h` systemd unit.
3. Install ordinary runtime files under `~/.local/libexec/` and
   `~/.config/systemd/user/`.
4. Reenable and restart only the watchdog, then prove the app-server PID and
   socket did not change.
5. Keep the old OA files untouched until that dirty worktree can be cleaned
   independently.

## RED and GREEN report

| Guarantee | Validation | Result | Evidence |
| --- | --- | --- | --- |
| Machine-level source exists under `myagent` rather than an application repository | `bash tests/test_codex_app_server_watchdog.sh` | PASS | RED exited `1` with `missing machine-level watchdog asset`; GREEN prints `test_codex_app_server_watchdog: PASS` |
| Unit and source contain no OA runtime dependency | Focused test plus `systemctl --user show` | PASS | Loaded `WorkingDirectory=/home/zhanxp` and runtime `ExecStart` under `~/.local/libexec` |
| Historical continuity guards survive the move | Focused shell regression | PASS | Version mismatch, listening-socket cleanup guard, failure threshold, and lock-safe loop sleep assertions pass |
| Runtime installation cannot call real systemd during tests | Fake `systemctl` plus `CODEX_WATCHDOG_INSTALL_ONLY=1` | PASS | Staging completed and the fake systemctl log stayed empty |
| Replacing the watchdog does not replace app-server | Live PID and socket comparison | PASS | app-server PID `654445` and socket inode `6770` were unchanged; watchdog moved from PID `777851` to `1079702` |

RED checkpoints: `510dd28`, `ad2e424`, and `481a35d`.

## Live verification

- `bash tests/test_codex_app_server_watchdog.sh`
- `bash -n` for the watchdog, library, installer, and `configs/sync.sh`
- `systemd-analyze --user verify configs/codex/systemd/codex-app-server-watchdog.service`
- `bash configs/sync.sh codex-watchdog-install`
- `codex app-server daemon version`: CLI, managed Codex, and app-server all
  reported `0.144.6`
- `systemctl --user show codex-app-server-watchdog.service`: `active/running`,
  `KillMode=process`, `UMask=0077`, and `NRestarts=0`

## Coverage and known gaps

The focused shell test covers the migration boundary and the watchdog decision
helpers. No forced three-failure live restart was performed because that would
intentionally disconnect the session whose continuity is being protected.
ShellCheck is not installed on this machine. The inactive watchdog copies in
the dirty OA worktree remain in place for non-destructive cleanup later; neither
the loaded unit nor its enablement link references them.
