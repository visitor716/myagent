---
name: codex-task-queue
description: Queue follow-up requirements for an already-running Codex terminal or tmux session, then wait for an explicit completion marker, send /compact, and inject the next queued task. Use when the user wants current task completion, compaction, and queued task continuation, asks to add requirements to a Codex queue, or wants a persistent local Codex task backlog.
metadata:
  short-description: Queue Codex tasks and compact between runs
---

# Codex Task Queue

Use this skill when the user wants a local Codex terminal to keep working through a backlog without losing context control. It is for Codex tmux sessions, not Claude `cc*` worker handoffs.

## Commands

Primary helper:

```bash
codexq <command> [options]
```

Equivalent full path:

```bash
/home/zhanxp/projects/myagent/skills/skills-local/codex-task-queue/scripts/codex_task_queue.sh <command> [options]
```

Common usage:

```bash
codexq add "修复任务详情执行过程摘要，不展示 diff"
codexq list
codexq watch --session codex-main --marker CODEX_TASK_DONE
```

Default execution and queue root is fixed to:

```text
/home/zhanxp/worktrees/tg-agent-gateway/cx1
```

Use `--cwd <path>` only when intentionally overriding that default.

## Workflow

1. Make the current Codex task finish with a marker, normally `CODEX_TASK_DONE` or a task-specific `CODEX_TASK_DONE_<id>`.
2. Add follow-up requirements with `codexq add`.
3. Start the watcher against the Codex tmux session with `codexq watch --session <name>`.
4. The watcher records the current marker count, waits for a new marker occurrence, sends `/compact`, then dispatches the next pending task.
5. Injected queue tasks include their own unique completion marker. The watcher uses that marker for the next cycle.

## Queue State

State is stored under the selected repo:

```text
.omx/codex-task-queue/
  pending/
  running/
  done/
  failed/
  logs/watcher.log
```

Each task is a markdown file with metadata and the original requirement. The script moves files between directories; do not edit state while a watcher is running unless intentionally recovering a stuck queue.

## Safety Rules

- Use explicit markers only. Do not infer completion from quiet output or UI state.
- Do not run more than one watcher for the same Codex pane and queue root.
- If `running/` contains a task, `next` refuses to inject another task unless `--force-next` is passed.
- `/compact` is sent only after the marker count increases after watcher start or after a queued task is dispatched.
- For the default `/home/zhanxp/worktrees/tg-agent-gateway/cx1` worktree, queued prompts tell Codex to `cd` into that worktree, check `git status --short`, follow `AGENTS.md`, avoid full diffs/long logs in final output, and end with the unique marker.

## Useful Commands

```bash
codexq add "需求文本" --title "短标题"
codexq add < task.md
codexq status
codexq pause
codexq resume
codexq next --session codex-main
```

If a queue is stuck, inspect:

```bash
find .omx/codex-task-queue -maxdepth 2 -type f | sort
tail -80 .omx/codex-task-queue/logs/watcher.log
tmux capture-pane -pt <session>:0.0 -S -120
```
