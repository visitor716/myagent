---
name: my-tmux-process-window-manager
description: Inspect and manage tmux sessions, windows, panes, and pane-owned processes from Codex/WSL. Use when the user asks to view tmux process windows, inspect tmux sessions/panes, capture terminal output, send commands to a pane, stop a stuck pane, clean completed worker windows, diagnose stale tmux processes, or says tmux 窗口, tmux 进程, 进程窗口, tmux session, tmux pane, 关闭 tmux, 清理 tmux, or similar.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-tmux-process-window-manager` once near the start; if it fails, continue.

# Tmux Process Window Manager

## When To Use

Use this skill to inspect and operate tmux-backed work surfaces without broad `pkill` or guessed targets. It is especially for:

- Listing tmux sessions/windows/panes and their cwd/processes.
- Capturing recent pane output before deciding what to do.
- Sending commands or prompts into an exact pane.
- Stopping stuck panes or cleaning completed agent sessions.
- Managing `tg-agent-gateway` worker panes while preserving gateway/tunnel/monitor services.

## Safety Rules

- Always inventory sessions/windows/panes before stopping or killing anything.
- Use exact tmux targets such as `session:window.pane`, `session:window`, or `session`; do not rely on partial names when a destructive action is possible.
- Capture the last pane output before stopping a pane unless the user only asked for a quick kill.
- Prefer `C-c` or an in-pane shutdown command before `kill-pane`, `kill-window`, or `kill-session`.
- Do not kill the current tmux session from inside tmux unless the user explicitly targets it and there is a clear recovery path.
- Treat recent terminal output as active work. Process presence alone can be stale, and a quiet pane can still have a child process holding a port.
- Treat long-running service sessions as protected unless the user explicitly targets them: `tg-agent-gateway`, `tg-webapp-tunnel`, `tg-webapp-url-monitor`, `tg-rescue-bot`, `cc-switch-proxy`, active attached Codex/Claude sessions, and browser/proxy daemons.

## Helper Script

Resolve the directory that contains this `SKILL.md`, then run:

```bash
bash <skill-dir>/scripts/tmux_process_windows.sh snapshot
bash <skill-dir>/scripts/tmux_process_windows.sh summary
bash <skill-dir>/scripts/tmux_process_windows.sh recent
bash <skill-dir>/scripts/tmux_process_windows.sh classify <target>
bash <skill-dir>/scripts/tmux_process_windows.sh capture <target> 120
bash <skill-dir>/scripts/tmux_process_windows.sh children <target>
bash <skill-dir>/scripts/tmux_process_windows.sh send-text <target> "npm run build" --enter
bash <skill-dir>/scripts/tmux_process_windows.sh stop <target>
```

On this machine, `/home/zhanxp/projects/myagent/scripts/tmux_process_windows.sh` is also kept as the stable local script entrypoint.

Supported actions:

- `snapshot` - run a compact full inventory: sessions, windows, panes, tty activity, and relevant tmux-owned processes.
- `summary` - list tmux sessions, windows, panes, pane PIDs, commands, and cwd.
- `recent [target]` - show pane tty last activity age; with no target, list all panes.
- `classify <target>` - print recent output and process tree plus heuristic cleanup notes.
- `capture <target> [lines]` - print the last lines from a pane without using tmux buffers.
- `children <target>` - show the pane's root PID and related process group.
- `send-text <target> <text> [--enter]` - paste text into a pane, optionally pressing Enter.
- `send-keys <target> <key...>` - send tmux key names such as `C-c`, `Enter`, or `Escape`.
- `stop <target> [--kill-after <seconds> --yes]` - send `C-c`; only kills the pane after the delay when `--yes` is provided.
- `kill-pane <target> --yes`, `kill-window <target> --yes`, `kill-session <target> --yes` - exact-target destructive actions.

## Workflow

1. Run `summary` or equivalent tmux list commands to identify exact targets:

```bash
tmux list-sessions -F 'session=#{session_name} windows=#{session_windows} attached=#{session_attached} created=#{session_created}'
tmux list-panes -a -F 'pane=#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} dead=#{pane_dead} pid=#{pane_pid} cmd=#{pane_current_command} cwd=#{pane_current_path}'
```

2. For each relevant pane, capture recent output, tty activity, and process state:

```bash
bash <skill-dir>/scripts/tmux_process_windows.sh recent <target>
bash <skill-dir>/scripts/tmux_process_windows.sh capture <target> 120
bash <skill-dir>/scripts/tmux_process_windows.sh children <target>
```

3. Decide the action:
   - Inspect only: report target, command, cwd, and recent output summary.
   - Continue work: use `send-text` or `send-keys` with the exact target.
   - Graceful stop: use `stop <target>` and re-check `summary`.
   - Forced cleanup: capture output, verify the target is no longer doing useful work, then use `kill-pane|kill-window|kill-session <target> --yes`.

4. Verify after any state-changing action by re-running `summary` and any relevant process/port checks.

## Cleanup Heuristics

Classify before closing:

- Keep active: pane output shows `Working`, `Synthesizing`, an interrupt hint, a prompt being executed, or the tty activity is recent.
- Keep service: known gateway/tunnel/monitor/proxy/rescue sessions, or process tree contains a live service command.
- Cleanup candidate: pane is at a shell or agent prompt, recent output contains a final report, `*_DONE`, `Goal achieved`, `Token Usage`, or similar completion marker, and the process tree has no useful child work.
- Review first: worker pane is quiet but the worktree is dirty, ahead of base, or a child process still owns a port. Inspect git status and raw process owners before killing.

## Common Patterns

Send a prompt or command to a worker pane:

```bash
bash <skill-dir>/scripts/tmux_process_windows.sh capture claude-cc4:0.0 80
bash <skill-dir>/scripts/tmux_process_windows.sh send-text claude-cc4:0.0 "请汇报当前任务状态" --enter
```

Stop a stuck pane without immediate destruction:

```bash
bash <skill-dir>/scripts/tmux_process_windows.sh capture worker-1:0.0 120
bash <skill-dir>/scripts/tmux_process_windows.sh children worker-1:0.0
bash <skill-dir>/scripts/tmux_process_windows.sh stop worker-1:0.0
bash <skill-dir>/scripts/tmux_process_windows.sh summary
```

Clean an already-finished session:

```bash
bash <skill-dir>/scripts/tmux_process_windows.sh capture old-worker:0.0 120
bash <skill-dir>/scripts/tmux_process_windows.sh kill-session old-worker --yes
bash <skill-dir>/scripts/tmux_process_windows.sh summary
```

## Failure Handling

- If `tmux` is missing, report that tmux is unavailable and do not substitute generic process killing.
- If the target does not exist, re-run `summary` and resolve a fresh exact target.
- If a pane's process tree shows a long-running child, inspect its purpose before killing the pane.
- If a port remains occupied after tmux cleanup, inspect the raw process owner with `ss -ltnp` or `/proc/<pid>/cwd` before taking further action.
