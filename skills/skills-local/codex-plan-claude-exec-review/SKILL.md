---
name: my-codex-workfolws
description: Use when tg-agent-gateway delivery should follow cx1 plan -> cx2 orchestrate -> worker execute -> observer report -> cx2 review -> master integrate/push, or when the user wants a Codex plan handed to Claude workers with observer coverage and a cx2 review gate. Triggers include "安排 cc", "安排cc", "把计划交给 Claude 做", "Claude 做完你 review", "Codex 规划 Claude 执行 Codex 检查", "plan to Claude execute to Codex review", and similar handoff/review workflows.
metadata:
  short-description: cx1 plan, cx2 orchestrate/review, workers execute, master integrates
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-codex-workfolws` once near the start; if it fails, continue.


# cx1 Plan -> cx2 Orchestrate -> Worker Execute -> Observer Report -> cx2 Review -> Master Integrate

Use this skill to coordinate the `tg-agent-gateway` delivery loop where `cx1`
owns plan-only work, `cx2` owns execution orchestration and review, worker
worktrees own implementation/repair, `cc2` observes by default, and `master`
owns final integration, verification, runtime refresh, `/app` release
notification, and push when requested or explicitly included in the workflow.

## Core Workflow

1. `cx1` produces or confirms a decision-complete plan, task split,
   acceptance criteria, and handoff document. `cx1` remains plan-only except
   for planning, prompt, or skill documentation updates.
2. `cx2` reads the `cx1` plan, decides whether the work is parallel or serial,
   and creates handoff prompt files in `.omx/claude-handoffs/<task-slug>.md`.
3. `cx2` picks implementation worker(s) using the requested worker or the
   "TG Gateway CC Worker Selection" policy. Keep `cc2` as the default
   read-only observer and default implementation workers to `cc3`-`cc10`.
4. `cx2` verifies selected worktrees are clean and idle. In `tg-agent-gateway`,
   do not invent an ad hoc fallback when configured workers are unavailable.
5. Worker(s) execute only inside their assigned worktree/branch. They must not
   edit `master` directly.
6. `cx2` launches `cc2` as a read-only observer whenever `cc2` is clean and
   idle. If `cc2` is unavailable, continue implementation and report the
   observer gap.
7. The observer reports execution status, diff summary, verification evidence,
   stall/failure blockers, and final result path back to `cx2`.
8. `cx2` reviews completed worker diff(s) read-only against the `cx1` plan and
   verification evidence. `cx2` does not implement, merge, commit, or push.
9. If `cc` review fails, `cx2` stops `cc` retry loops immediately and moves to
   the dynamic fallback lane.
10. Repair the final candidate with the first clean idle Codex worker in
   `cx3 -> cx4 -> cx5` (one shot, no parallel), launched in a long-lived
   visible Codex terminal by default.
11. Route the repaired candidate back to `cx2` for review gate: `pass/fail`,
   blocking findings, and verification evidence.
12. On `cx2` pass, `cx2` outputs a master integration candidate containing the
   worker/branch/patch, verification evidence, risks, and recommended merge
   scope. `cx2` does not merge or push.
13. `master` integrates only candidates that passed `cx2` review, runs final
   verification, applies runtime refresh when applicable, sends the `/app`
   release notification, and pushes only when the user asked or the workflow
   explicitly includes push.
14. If review fails at any stage, try the next `cx3/cx4/cx5` worker once; do
   not fallback to another `cc` attempt.
15. Keep the completed worker tmux session open until the branch is merged into
   `master` or explicitly discarded/cleaned; do not close it merely because a
   worker finished or the patch was copied elsewhere.

## Parallel/Serial Dispatch Rules

- 并行: independent files, independent features, independent tests, or clearly
  separable UI/API surfaces may run in parallel workers when their diffs can be
  reviewed and merged independently.
- 串行: shared files, the same API, the same state machine, the same UI page,
  shared task lifecycle semantics, or work depending on a previous result must
  run serially.
- For parallel work, `cx2` must name each lane, worker, expected diff scope,
  and verification command before launch. Use one `cc2` observer prompt that
  lists all exact worker sessions/worktrees.
- For serial work, `cx2` launches only the next worker needed for the current
  dependency step, reviews that result, and then decides the next handoff.
- Never run multiple repair workers in parallel. Repair worker default order
  remains `cx3 -> cx4 -> cx5`.

## Dynamic Fallback Orchestration

Apply this flow when `cc` fails after first attempt.

Failure criteria:

- worker produced no diff
- required verification command(s) failed or not run
- `cx2` review reports blocking issue
- worker hung/no terminal output/unfinished completion marker
- diff includes out-of-scope or unrelated files

Fallback rules:

- Do not relaunch `cc` workers for the same task after the first failure.
- Run exactly one repair worker pass using the first clean idle candidate in order: `cx3`, then `cx4`, then `cx5`.
- Launch CX repair/review workers in visible Windows Terminal + tmux Codex CLI sessions by default. Do not use headless `codex exec` unless the user explicitly asks for a background/headless run or the workflow text explicitly marks the run as automated and non-observable.
- Repair prompts must contain:
  - cc failure summary
  - target diff scope
  - required verification commands + observed results
  - explicit prohibitions (no command semantic change, no callback/data/permission changes, no unrelated files)
- If a repair worker is unavailable or fails criteria, continue to the next `cx` candidate.
- If all `cx3`/`cx4`/`cx5` are unavailable or all fail, stop before master integration and report blocked state.
- After repair, send only the final candidate to `cx2` review gate.

## Worker Visibility and Branch Isolation

- Implementation, repair, and review workers must run inside their assigned worker worktree/branch, never in the main checkout.
- Default worker launches are visible:
  - `cc*` workers use `launch_claude_worker_terminal.sh` and a visible Claude Code terminal.
  - `cx*` workers use `launch_codex_worker_terminal.sh` without `--exec`, so the Windows Terminal tab/window attaches to a tmux session that shows a live Codex CLI.
- Any explicit request to start a `cxN` branch/session uses the same visibility contract as `cc`: open Windows Terminal, create or attach a tmux session named `codex-<task-slug>`, start interactive `codex` with the prompt file content as the initial prompt, verify the pane command is `codex` and the TUI has rendered `OpenAI Codex`, and leave the session available after completion.
- Do not start `cx*` workers from the current Codex pane, `nohup`, a detached shell-only tmux pane, or `codex exec` unless the user explicitly asks for headless/background execution.
- After launching a visible `cx*` worker, verify `tmux list-panes` shows `pane_current_command` as `codex`. If it shows `bash`, a completed shell prompt, or no Codex process, report that no live agent is running.
- Headless `codex exec` is an exception path only. If it is used, say explicitly that there will be no visible agent terminal and why that exception was chosen.
- If a visible Codex terminal cannot be launched and the task can be delegated to Claude Code instead, prefer a clean idle `cc*` visible Claude Code worker over a silent headless Codex run. Keep the normal no-cc-retry rule after a failed `cc` implementation.

## Automatic Terminal Launch

When handing off to `cc*` or `cx*` workers, this skill automatically launches a Windows Terminal window/tab for real-time observability:

- Script locations:
  - `scripts/launch_claude_worker_terminal.sh` (cc/fix to Claude Code)
  - `scripts/launch_codex_worker_terminal.sh` (cx interactive Codex CLI by default; `--exec` for headless one-shot runs)
- Claude Code default behavior:
  - Uses `wt.exe` at `/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe`
  - Opens a new tab in the current window
  - Creates/attaches to a tmux session named `claude-<task-slug>`
  - Starts `claude --permission-mode auto`
  - Pastes the task prompt into Claude
  - Does not send `/compact` after task completion by default
  - If `--compact` is set, appends a task completion marker and sends
    `/compact` through tmux only after that marker appears

- Codex worker default behavior:
  - Uses the same `wt.exe` path and opens a visible Windows Terminal tab/window.
  - Creates/attaches to a tmux session named `codex-<task-slug>`.
  - Starts interactive `codex` inside the selected worktree and keeps the tmux session long-lived.
  - Prints observation commands before launch and verifies the pane is `pane_current_command=codex`.
  - Does not run in the caller's hidden/current Codex pane when Windows Terminal is unavailable; it prints a manual fallback command instead.

- Observation commands output to user:
  ```bash
  cd <worker-worktree>
  tmux attach -t claude-<task-slug>
  tmux attach -t codex-<task-slug>
  ```

- File change watch command:
  ```bash
  watch -n 1 'git status --short && echo && git diff --stat'
  ```

- If `wt.exe` is not available, falls back to manual execution mode and prints the command to run.

For generic, non-`tg-agent-gateway` handoffs, if the exact target tmux session
already exists, the launcher attaches to it and does not resend the prompt or
add a new compact watcher. Use a fresh `--task-slug` for a new task.

For `tg-agent-gateway` `ccN` worker handoffs, do not attach to an existing
same-worker Claude session. If any tmux session named `claude-<ccN>-*` already
exists, treat that worker as busy. Generic "安排 cc" requests must skip that
worker and continue scanning `cc2`-`cc10`; fixed-worker requests such as
"安排 cc2" must report waiting/unavailable for that worker. Do not resend the
prompt and do not start a second task in the same `ccN`.

## TG Gateway CC Worker Selection

Use this policy whenever the target repo is `/home/zhanxp/projects/tg-agent-gateway` and the user asks to "安排 cc", "安排cc", "让 cc 做", or otherwise wants a Claude Code worker.

Default implementation scan order when the `cc2` observer is enabled:

```text
cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10
```

Reserved observer:

```text
cc2
```

Selection rules:

- If the user names a specific implementation `ccN`, use it only if it is clean and idle; otherwise report why it is unavailable and choose the next clean idle worker only when the user asked for generic cc execution.
- For generic "安排 cc" requests, keep `cc2` free for observation and scan `cc3` through `cc10` in order for implementation.
- Use `cc2` as an implementation worker only when the user explicitly names `cc2`, explicitly disables observer coverage, or explicitly accepts using `cc2` after all `cc3`-`cc10` implementation candidates are unavailable.
- If every implementation candidate is dirty, conflicted, DB-busy, or has an active incompatible tmux/Claude session, leave the task waiting. Do not default to `cc4`, do not reuse a dirty worktree, and do not create a throwaway worktree for this repo unless the user explicitly asks.
- Treat a worktree with unrelated local modifications, unresolved conflict markers, or `UU` status as unavailable for a fresh task.
- Treat a worker as busy if any tmux session named `claude-<worker>-*` already
  exists. For generic "安排 cc", skip that worker and continue scanning. For a
  fixed worker request, report the existing session and wait; do not attach,
  resend the prompt, or launch a new task.
- Treat a worker as busy if `data/gateway.sqlite` has active rows for that worker or if tmux shows a Claude session whose pane cwd is inside that worker worktree. Git cleanliness alone is not enough.
- Before permanently skipping a worker for tmux busy, check whether the tmux pane is a stale completed Claude session whose work is already resolved. Only close that session if the worker branch is merged into `master`, or the worker diff was explicitly discarded and the worktree is clean. If the work was only copied into a non-master checkout or is still waiting for merge/discard, keep the tmux session open and treat the worker as busy.

Availability audit:

```bash
git -C /home/zhanxp/projects/tg-agent-gateway worktree list --porcelain
for cc in cc2 cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10; do
  wt="/home/zhanxp/worktrees/tg-agent-gateway/$cc"
  printf '\n== %s ==\n' "$cc"
  git -C "$wt" status --short 2>/dev/null || echo "missing worktree"
  sqlite3 /home/zhanxp/projects/tg-agent-gateway/data/gateway.sqlite \
    "select id,status,worker,recommended_agent,title from tasks where status in ('running','queued','planned','pending','processing') and (worker='$cc' or recommended_agent='$cc') order by created_at desc limit 5;" 2>/dev/null || true
done
tmux list-panes -a -F '#{session_name} #{pane_current_path} #{pane_current_command}' 2>/dev/null |
  rg '/home/zhanxp/worktrees/tg-agent-gateway/(cc2|cc3|cc4|cc5|cc6|cc7|cc8|cc9|cc10)|claude-cc([2-9]|10)' || true
tmux list-sessions -F '#{session_name}' 2>/dev/null |
  rg '^claude-cc([2-9]|10)-' || true
```

Stale completed-session cleanup:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge-master/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3"
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge-master/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3" --apply
```

Only run the `--apply` cleanup after proving each target worker branch has been
merged into `master`, or after intentionally discarding its diff and confirming
the worktree is clean. A completed Claude final report is not enough by itself.

Report the selected worker and the skip reason for earlier candidates. If no worker is available, report "waiting" with the blocking reasons instead of launching Claude.

## CC2 Observer Policy

Use this policy whenever `tg-agent-gateway` implementation work is assigned to
any `cc*` worker other than `cc2`, or whenever multiple `cc*` workers are
launched for related implementation tasks.

- Default observer worker: `cc2`.
- `cc2` is read-only in observer mode. It must not edit files, run fix commands,
  merge, commit, push, or send prompts into implementation workers.
- Start the observer after the implementation worker terminal(s) have been
  launched and exact tmux session names are known.
- The observer should monitor exact worker sessions and worktrees, for example
  `claude-cc4-<task-slug>` and
  `/home/zhanxp/worktrees/tg-agent-gateway/cc4`.
- The observer reports completion status, final worker result, diff summary,
  verification evidence, obvious stalls or failures, and the final result path
  back to the `cx2` leader pane when that pane is known. If the `cx2` pane is
  not known, the observer writes a result file under `.omx/observers/` and
  reports the path in the final user-facing status.
- If `cc2` is dirty, has an active `claude-cc2-*` session, has active DB rows,
  or otherwise fails the normal availability checks, do not reuse it. Continue
  the implementation task and report `cc2 observer unavailable: <reason>`.
- If the implementation worker is explicitly `cc2`, do not launch a separate
  `cc2` observer for that same task.
- For multiple concurrent `cc*` implementation workers, use one `cc2` observer
  prompt that lists all exact target sessions/worktrees instead of launching
  multiple observer tasks in `cc2`.

CC2 observer prompt shape:

```text
你是 cc2 观察者，只读观察，不实现、不修改、不提交、不合并。

观察目标：
- [worker/session/worktree list]

任务：
- 每隔一段时间查看目标 tmux pane 输出、worker git status/diff stat、验证命令结果线索。
- 如果目标 worker 完成，提取最终报告和验证结果。
- 如果目标长时间没有新输出、失败、无 diff、验证失败或越权修改，报告 blocker。
- 将结果通知 cx2 pane（若提供），并写入 .omx/observers/<slug>.result.md。
- 最终报告必须包含执行状态、diff 摘要、验证证据、stall/failure blocker 和结果文件路径。

禁止：
- 不修改任何文件。
- 不向目标 worker 输入内容。
- 不 kill / compact / restart 任何目标 session。
- 不粘贴长日志或完整 diff。
```

## Selected CC Worker Handoff

After a worker has passed the selection checks, launch that selected `cc*`
worker. If the user named a specific worker and it is unavailable, do not
silently use it; either use the next clean idle worker for a generic cc request
or report waiting/unavailable for a truly fixed-worker request.
Post-task `/compact` is disabled by default for every `cc*` worker launched
through this skill.

1. Resolve the worker worktree, normally
   `/home/zhanxp/worktrees/tg-agent-gateway/<worker>`.
2. Check `git -C <worktree> status --short` before handoff.
3. Immediately before launching, check for an existing same-worker tmux
   session:
   ```bash
   tmux list-sessions -F '#{session_name}' 2>/dev/null | rg '^claude-<worker>-'
   ```
   If it exists, the worker is busy. For generic cc dispatch, skip to the next
   clean idle worker. For a fixed `ccN` request, report waiting/unavailable.
   Do not attach to that session, resend the prompt, or launch another task for
   the same worker.
4. Write `.omx/claude-handoffs/<task-slug>.md` in the main checkout.
5. Launch with the worker name as the tab title:
   ```bash
   scripts/launch_claude_worker_terminal.sh \
     --worktree /home/zhanxp/worktrees/tg-agent-gateway/<worker> \
     --task-slug <worker>-<task-slug> \
     --prompt-file /home/zhanxp/projects/tg-agent-gateway/.omx/claude-handoffs/<worker>-<task-slug>.md \
     --title <worker>
   ```
6. The launcher has a defensive `tg-agent-gateway` `ccN` guard: if `--title`
   or the worktree basename resolves to `ccN` and any `claude-<ccN>-*` tmux
   session already exists, it prints `SKIP <ccN>: existing Claude tmux session
   <session>` and exits successfully before writing the prompt copy, opening
   Windows Terminal, attaching, or starting Claude.
7. Do not pass `--compact` unless the user explicitly requests post-task
   Claude context compaction.
8. Report the tmux attach command. After Claude finishes, `cx2` reviews the
   worker diff instead of asking the worker for another summary.
9. Leave the tmux session open after completion until the branch has a final
   disposition: merged into `master`, or explicitly discarded with a clean
   worktree.

## Terminal Launch Script Usage

```bash
scripts/launch_claude_worker_terminal.sh \
  --worktree <path> \
  --task-slug <slug> \
  --prompt-file <path> \
  [--title <tab-title>] \
  [--terminal-mode tab|window] \
  [--compact] \
  [--no-compact] \
  [--compact-wait <seconds>] \
  [--dry-run] [--verbose]
```

The Windows Terminal tab title defaults to the worktree basename, so any
handoff launched in `/home/zhanxp/worktrees/tg-agent-gateway/ccN` opens as
`ccN` instead of `wsl.exe`. Use `--title` to override this default.

For `/home/zhanxp/worktrees/tg-agent-gateway/ccN`, the launcher derives the
worker from `--title` first, then from the worktree basename. If that worker has
an existing `claude-<ccN>-*` tmux session, it prints a `SKIP` line and exits 0.
This guard is intentionally limited to `tg-agent-gateway` cc worker worktrees;
non-cc and non-`tg-agent-gateway` handoffs keep the existing exact
`--task-slug` session reuse/attach behavior.

By default the launcher starts Claude Code, waits briefly for the UI, and sends
the handoff prompt without asking Claude to print a completion marker. It does
not send `/compact` after the task.

Codex worker terminal launches have two distinct modes:

- Default mode opens a real interactive Codex CLI TUI in Windows Terminal,
  starts `codex [PROMPT]` inside the selected worktree with the prompt file
  content as the initial prompt. Use this whenever the user asks to "启动 cxN", wants to see a worker
  terminal, or expects a visible Codex CLI session. This mode is long-lived:
  the terminal attaches to tmux and should remain available just like a `cc`
  worker terminal after the task completes.
- The launcher prints the attach/watch commands up front, opens Windows
  Terminal with `--window 0 new-tab` by default, and then verifies the tmux pane
  is actually running `codex`. If verification fails, treat the worker as not
  launched rather than assuming a background run succeeded.
- Prompt injection for Codex should use the CLI's initial `[PROMPT]` argument.
  Do not multi-line paste into the TUI after launch; it can split the first line
  into the active prompt and queue the rest as follow-up input.
- `--exec` mode runs headless `codex exec` with the prompt piped through stdin.
  Use it only when the user explicitly accepts a background/headless run or no
  visible worker terminal is needed. For normal `安排cc` fallback repair and
  `cx2` review gate, prefer interactive mode without `--exec`.

Interactive Codex worker starts for `cx3/cx4/cx5` and `cx2` use:

```bash
scripts/launch_codex_worker_terminal.sh \
  --worktree <path> \
  --task-slug <slug> \
  --prompt-file <path> \
  --title <cx-title> \
  --model <model> \
  --reasoning-effort <effort> \
  [--dry-run]
```

Headless one-shot Codex worker runs use the same launcher with `--exec`:

```bash
scripts/launch_codex_worker_terminal.sh \
  --worktree <path> \
  --task-slug <slug> \
  --prompt-file <path> \
  --title <cx-title> \
  --model <model> \
  --reasoning-effort <effort> \
  --exec
```

When verifying a CX terminal start, check the tmux pane command. A successful
interactive launch must show `pane_current_command` as `codex`; if it shows a
completed shell prompt after `codex exec`, that was a headless run, not a
Codex CLI terminal.

## TG Gateway CX Worker Selection

Use this policy for post-cc repair, `cx2` review gates, and explicit requests
to start a `cxN` branch/session.

Default scan order:

```text
cx3 cx4 cx5
```

Selection rules:

- Choose the first worker that is clean, idle, and not blocked by existing `tmux` worker session.
- If the user names a specific `cxN`, use that worker only if it is clean, idle, and can be started in a long-lived visible Codex terminal; otherwise report it unavailable instead of falling back to headless execution.
- Never run multiple repair workers in parallel.
- Keep the repaired worker command consistent:
  - `model`: `gpt-5.3-codex-spark`
  - `model_reasoning_effort`: `xhigh`

Repair worker launch pattern (visible by default):

```bash
/home/zhanxp/projects/myagent/skills/skills-local/codex-plan-claude-exec-review/scripts/launch_codex_worker_terminal.sh \
  --worktree /home/zhanxp/worktrees/tg-agent-gateway/<cxN> \
  --task-slug <cxN>-<task-slug>-repair \
  --prompt-file /home/zhanxp/projects/tg-agent-gateway/.omx/claude-handoffs/<cxN>-<task-slug>-repair.md \
  --title <cxN> \
  --model gpt-5.3-codex-spark \
  --reasoning-effort xhigh
```

After launch, verify the pane:

```bash
tmux list-panes -a -F '#{session_name} #{pane_current_path} #{pane_current_command}' |
  rg 'codex-<cxN>|/home/zhanxp/worktrees/tg-agent-gateway/<cxN>'
```

Only use `--exec` or direct `codex exec` for repair if the user explicitly asks
for headless/background execution; if used, report that no visible agent will be
present.

If all candidates are unavailable or fail, report blocked rather than creating extra cc retries.

## CX2 Review Gate

- `cx2` review is mandatory only after repair candidate is ready.
- `cx2` is review-only. It must not implement, modify files, merge, commit, or
  push.
- `cx2` output requires clear `pass/fail`, blocking findings, verification
  evidence, and a master integration recommendation.
- On pass, `cx2` outputs only the candidate worker/branch/patch, verification
  evidence, risks, and recommended master merge scope.
- On fail, `cx2` routes the task to the next allowed repair worker or reports
  blocked state. It must not silently fix the worker diff itself.
- `cx2` review launch pattern (visible by default):

```bash
/home/zhanxp/projects/myagent/skills/skills-local/codex-plan-claude-exec-review/scripts/launch_codex_worker_terminal.sh \
  --worktree /home/zhanxp/worktrees/tg-agent-gateway/cx2 \
  --task-slug cx2-<task-slug>-review \
  --prompt-file /home/zhanxp/projects/tg-agent-gateway/.omx/claude-handoffs/cx2-<task-slug>-review.md \
  --title cx2 \
  --model gpt-5.5 \
  --reasoning-effort xhigh
```

- If review fails, route to next available repair worker (`cx3/cx4/cx5` order), then stop and report if no additional worker remains.

## Worktree Setup Checks

- Inspect `git status --short` in candidate worker worktrees before handoff; do not layer a new task on unresolved conflicts or unrelated dirty edits.
- For `tg-agent-gateway`, also inspect active DB rows and tmux panes before handoff; a clean git status does not prove the worker is idle.
- For `tg-agent-gateway`, if no `cc2`-`cc10` candidate is clean and idle, leave the task waiting instead of creating an extra worktree.
- If no clean worker worktree is available, create an isolated one with `git worktree add -b wt/<task-slug> <path> HEAD` or the requested base ref. Do not commit from this temporary worktree unless explicitly asked.
- If the new worktree lacks dependencies but the main checkout has them, prefer installing normally when appropriate. For quick local verification only, a `node_modules` symlink can be excluded via the worktree's local `.git/info/exclude`; do not edit tracked ignore rules just for that symlink.
- Run one cheap baseline verification before handoff when possible, such as `npm run type-check`, so Claude does not inherit a broken worktree.

## Handoff Prompt File

Before launching the terminal:

- Create `.omx/claude-handoffs/` directory if it doesn't exist.
- Write the handoff prompt to `.omx/claude-handoffs/<task-slug>.md`.
- Generate a clean task slug from the task description (lowercase, alphanumeric + hyphens only).
- The launcher starts Claude and pastes the prompt into the tmux pane.
- Only when launched with `--compact`, it appends a completion marker
  instruction and sends `/compact` after the marker appears.
- Keep the prompt file around until the task completes for debugging/reattachment.

## Handoff Prompt Template

Use this when creating the Claude task:

```text
请按下面计划实现。只在你的 worker worktree 中修改，不要直接修改主仓，不要提交无关文件。

[PASTE CODEX PLAN]

执行要求：
- 保持改动最小，遵循当前仓库 AGENTS.md。
- 不要修改计划未覆盖的业务语义、命令语义、callback_data 或权限边界。
- 遇到与计划冲突的现有代码，先按现有代码约束收敛实现，不做大范围重构。
- 完成后运行计划中的验证命令；如果命令失败，继续修复直到通过，或明确说明 blocker。
- 如果 Claude Code CLI 或会话 UI 暴露 token/usage 信息，请在最终回复中简短报告；如果没有暴露，写 `cc: unavailable`，不要估算或编造。
- 最终回复必须简短，不要粘贴完整 diff、长日志、完整测试输出或大段终端记录。

完成后输出：
1. Changed Files
2. Summary
3. Verification
4. Risks
5. Token Usage
```

### CX Repair Prompt Template

Use this when `cc` failed and a `cx` worker is taking over:

```text
请修复上一轮实现中的问题，只在当前 worker worktree 修改，不要改主仓。

失败摘要：
- [cc 的具体失败原因，含验证命令和失败结果]

目标范围：
- [允许改动文件/目录范围]

验证要求：
- [required commands]

禁止事项：
- 不改命令语义 / callback_data / 权限边界
- 不改无关文件
```

## Token-Efficient Handoff

- Tell Claude to summarize verification by command and result only. Do not ask Claude to include full logs, full diffs, or long terminal tails.
- If Claude needs to preserve detailed evidence, have it leave evidence in files or logs inside the worktree and mention the path briefly.
- Ask Claude to include token/usage only when the CLI exposes it directly; otherwise it must report `cc: unavailable`.
- Codex should not paste Claude's long final output into review context. Use Claude's short report only as a pointer to what to inspect.

## Claude Fix Loop

When `cx2` review finds a defect in `cc` work, do not relaunch another `cc` for the same task.

- Create a repair prompt from findings (failure summary, evidence, expected behavior, allowed scope, required verification).
- Keep the fix prompt compact; only send one focused CX repair hop at a time.
- Send the repair task to the selected `cx3 -> cx4 -> cx5` worker unless the target `cx` worktree/work session is unavailable.
- If repair succeeds, route final candidate to `cx2` review immediately.
- If repair fails on the same fallback worker, move to the next candidate once. If all fail, `cx2` stops this automated loop and reports the blocker instead of merging.
- After each repair attempt, `cx2` repeats the same token-efficient review: status, diff stat, targeted diffs, focused tests.

Fix prompt shape:

```text
请修复上一轮实现中的以下问题。仍然只在当前 worker worktree 修改，不要改主仓。

问题：
- [one concise finding with file/line or command evidence]

期望：
- [specific expected behavior]

限制：
- 不做无关重构，不改命令语义/callback_data/权限边界。
- 最终只输出 Changed Files / Summary / Verification / Risks / Token Usage，不粘贴长日志或完整 diff。
- Token Usage 中只报告可直接读取到的 usage；拿不到就写 `cc: unavailable`。

验证：
- [focused commands]
```

## CX2 Review Checklist

When Claude finishes, review before accepting:

- Confirm the worker and worktree path are the expected ones.
- Start with `git status --short` and `git diff --stat` in the worker worktree.
- Open only the necessary file diffs with `git diff -- <path>` or targeted slices. Avoid loading full repo diffs unless the stat shows a small bounded change.
- Compare implementation behavior to the `cx1` plan using direct diff inspection, not Claude's summary.
- Check that tests or verification commands were actually run and are relevant. Prefer rerunning focused commands over reading long captured logs.
- Independently rerun the most relevant verification when it is cheap. Treat Claude's claimed verification as evidence to check, not as final proof.
- Flag unrelated rewrites, deleted safeguards, broad refactors, untracked generated files, or hidden config/secret changes.
- Watch for module-load side effects introduced by the patch. In TypeScript repos, helpers that import global env/config modules can make unit tests fail before they execute; prefer side-effect-light helpers or explicit env setup in tests.
- For WebApp task/message/detail changes in `tg-agent-gateway`, trace the actual click path end to end: card state update, API call, detail-sheet open, task-detail fetch, and event-stream fetch. Every dynamic `taskId` URL should use the shared encoding helper; do not accept raw `/tasks/${id}` interpolation when sibling endpoints already encode IDs.
- For file-persisted task state such as `data/task-messages.json`, verify tests route writes to a temporary path before importing code that writes messages. Do not let unit tests write fixture task IDs into the real local data file, because that creates phone-visible messages whose task detail cannot resolve.
- For package scripts that already include a test path, do not assume `npm run <script> -- <file>` narrows the run. Use the underlying test binary directly when you need a single focused test, for example `./node_modules/.bin/vitest run tests/unit/foo.test.ts`.
- Use code-review style output: findings ordered by severity, with file and line references when available.
- If no issues are found, emit the master integration candidate rather than
  asking Claude for another report or merging from `cx2`.

## Master Integration Lane

`master` is the only final integration/publish lane. `cx2` passes candidates
to `master`; `cx2` does not apply the patch, merge, commit, push, or perform
runtime release actions.

Master integration rules:

- Consume only candidates that passed `cx2` review.
- Start with `git status --short`, `git diff --stat`, and the candidate
  worker/branch/patch summary from `cx2`.
- When the main checkout already has user or parallel-agent edits, do not apply
  a worker patch blindly. Read the current main files, then merge only the
  accepted worker behavior into that current version. Preserve unrelated
  main-checkout changes and rerun relevant verification in the main checkout.
- If final verification fails in `master`, do not directly repair in `master`.
  Return the failure evidence to the `cx2` repair/review lane.
- Run build/typecheck or the verification commands appropriate to the accepted
  change. For docs-only or skill-only changes, read-only diff/grep checks are
  enough unless scripts/code were changed.
- Apply the runtime refresh lane when the accepted change can affect the
  running gateway/WebApp, then send the latest `/app` release notification.
- Push only when the user asked for push or the workflow explicitly includes
  push.
- If an accepted worker patch is staged/applied but not committed in the same
  turn, record the source worker, changed main files, backup patch path if any,
  and tmux session name in the final report. The next `merge` should use the
  `worktree-merge-master` Accepted Patch Lane so the main patch is committed,
  duplicate worker diff is backed up/cleaned, and worker tmux is closed only
  after final disposition.

## Worker Tmux Close Gate

For `tg-agent-gateway` `cc*` workers, a completed Claude report does not free
the worker. Close the worker tmux session only after one of these is true:

- The worker branch/diff has been merged into `master` and the worker worktree
  is clean.
- The worker output has been intentionally rejected or superseded, its diff has
  been discarded, and the worker worktree is clean.

Do not close the tmux session merely because the patch was applied to `cx1`,
`cx2`, or another intermediate checkout. Until the branch is merged to `master`
or discarded, keep the session visible as a live reminder and treat that worker
as unavailable for new handoffs.

## TG Gateway Runtime Refresh

For `/home/zhanxp/projects/tg-agent-gateway`, `master` owns the
post-integration runtime refresh after accepted changes. Do not make the user
restart the server for ordinary validation.

Use this rule after final verification in the main checkout:

- If the accepted change affects `src/`, backend routes, bot behavior, runner
  behavior, built WebApp assets, API contracts, or phone-side acceptance, run:
  ```bash
  npm run build
  npm run webapp:build
  ```
- Then restart the local gateway in tmux:
  ```bash
  tmux send-keys -t tg-agent-gateway:0.0 C-c
  tmux send-keys -t tg-agent-gateway:0.0 'npm run start 2>&1 | tee -a logs/runtime/gateway.log' Enter
  sleep 3
  tmux capture-pane -pt tg-agent-gateway:0.0 -S -80
  ps -ef | rg 'node dist/index.js|npm run start'
  ```
- If the `tg-agent-gateway` tmux session is missing, start it explicitly:
  ```bash
  tmux new-session -d -s tg-agent-gateway 'cd /home/zhanxp/projects/tg-agent-gateway && npm run start 2>&1 | tee -a logs/runtime/gateway.log'
  ```
- For WebApp-only edits while the Vite dev server/tunnel is the active phone
  entrypoint, HMR may be enough during iteration. For final acceptance, still
  build and restart when the user expects to validate from Telegram.
- Do not restart for docs-only, skill-only, test-only, or other changes that
  cannot affect the running gateway/WebApp.
- After restart, send the latest `/app` release notification through the
  existing repo/skill release path, then report that the user can reopen the
  Telegram WebApp for acceptance and mention any runtime log errors if startup
  did not look clean.

## Review Commands

Prefer read-only commands such as:

```bash
git -C <worker-worktree> status --short
git -C <worker-worktree> diff --stat
git -C <worker-worktree> diff -- <path>
git -C <worker-worktree> log --oneline --decorate -5
```

Run tests only if they are non-destructive for the repo and needed to validate the claim. Capture the command status and key failure lines; do not read or paste full test logs unless the failure cannot be diagnosed otherwise.

## Token Usage Reporting

For final user-facing reports after arranging a `cc*` worker, include a short
`Token Usage` section:

- `codex`: report exact token usage only if the current Codex runtime exposes it
  directly. If not available, write `unavailable`.
- `cc`: report exact Claude Code usage only if Claude's final output, CLI
  status, or captured pane exposes it directly. If not available, write
  `unavailable`.
- Do not estimate token counts from elapsed time, output length, or billing
  hints. It is better to mark usage unavailable than to invent numbers.

## Rules

- `cx1` planning can happen in the planning checkout; worker implementation must happen in the selected worker worktree; `cx2` review is read-only; final integration happens only in `master`.
- Do not push unless the user explicitly asks or the workflow explicitly includes push.
- If the top-level task asks for end-to-end delivery, then a passing worker implementation should be integrated by `master` according to repo rules after `cx2` review pass. If commit/merge authority is unclear, `cx2` reports "ready to merge" instead.
- Prefer `git apply` or a normal branch merge in `master` only after checking `git status --short`, `git diff --stat`, and final verification in the target checkout. Never merge unrelated dirty worktree changes.
- Do not silently fix worker implementation during the review phase; first identify findings and route:
  - `cc` failure -> single cx repair hop (`cx3/cx4/cx5` in order)
  - repair success -> `cx2` review gate
  - only after gate pass -> master integration
- If `cx3/cx4/cx5` repair path is exhausted or blocked, pause and report rather than creating another `cc` retry loop.
- If the user provides only a plan and asks for handoff, `cx2` generates the worker prompt and orchestration plan. If the user provides worker completion output, `cx2` starts review.
