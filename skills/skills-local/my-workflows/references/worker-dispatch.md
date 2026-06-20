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

## Parallel CC Read-Only Review Lane

Use this lane when the user asks for multiple `cc` workers to review at the
same time, for example `安排多个cc 同时review`.

1. Define non-overlapping review lanes before launch. Split by contract surface
   (for example DB/routing, API/service, WebApp UI, regression/tests) instead
   of asking every reviewer to inspect the same full diff.
2. Select clean idle reviewers from `cc3 -> cc10`. Keep `cc2` reserved as the
   single read-only observer. Skip dirty worktrees, DB-active workers, and any
   worker with an existing `claude-ccN-*` session.
3. Write one handoff file per reviewer under `.omx/claude-handoffs/`. Each
   prompt must say: read-only only, no implementation, no file edits, no commit,
   no merge, no push, first line `PASS` or `FAIL`, findings with file/line
   evidence, verification commands and result, risks, token usage if available.
4. Launch reviewers with `launch_claude_worker_terminal.sh`, then verify:
   `tmux list-panes` shows `pane_current_command=claude`, cwd is the assigned
   worktree, and `git status --short` remains clean.
5. Confirm each prompt actually started. If `tmux capture-pane` shows an idle
   Claude prompt with `[Pasted text #...]` but no working/output state, send one
   `Enter` to that specific session, wait a few seconds, and re-check. Do not
   resend the prompt.
6. Launch one `cc2` observer after the reviewer session names are known. The
   observer watches all reviewer sessions/worktrees and writes
   `.omx/observers/<slug>.result.md` with lane status, PASS/FAIL summary,
   blocking findings, verification evidence, and result path.
7. When the observer reports completion, synthesize the result. If any reviewer
   reports a blocking FAIL, do not merge or silently fix in `master`; route the
   finding through the normal `cx3 -> cx4 -> cx5` repair lane. If all PASS,
   report that the review gate passed and list Low/Info follow-ups separately.

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

After any visible Claude launch, verify the prompt was submitted, not only
pasted. A pane that still shows `[Pasted text #...]` at an idle prompt is not a
running reviewer/worker yet; send one `Enter` to that session and re-check the
pane before reporting the launch as live.

## Unified Worker Availability

`scripts/my_workflows.sh` uses one availability helper for
`select-cc-worker`, `select-cx-worker`, `review`/`cx2`, and `status`.
The helper output has these fields:

```text
worker
family
available
decision
reasons
worktree
dirtyCount
tmuxSessions
paneCwdHits
dbActiveRows
dbStaleRows
```

The same checks apply to `cc` and `cx` workers:

- worktree exists and `git status --short` is clean
- active DB rows in `data/gateway.sqlite`
- worker-family tmux session (`claude-<ccN>-*` or `codex-<cxN>-*`)
- any tmux pane whose cwd is inside the worker worktree
- `process_id` liveness for DB rows; stale DB rows become `db-stale-review`
  instead of live busy

Blocking reason vocabulary is shared by selection and status:
`dirty`, `busy-db-active`, `busy-tmux-session`, `busy-pane-cwd`, and
`missing-worktree`. `db-stale-review` is surfaced for review but does not by
itself make the worker unavailable.

Use verbose selection when diagnosing skips:

```bash
scripts/my_workflows.sh select-cc-worker --verbose
scripts/my_workflows.sh select-cx-worker --verbose
scripts/my_workflows.sh status
```

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
- Treat a worker as busy if the unified availability helper reports active DB
  rows, a worker-family tmux session, or any tmux pane cwd inside that worker
  worktree. Git cleanliness alone is not enough.
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
- One `cc2` observer covers every implementation worker in the current task
  group. Do not launch multiple observer tasks for the same group.
- The default observation scope is the explicit current task-group worker list;
  do not scan historical worker sessions.
- `cc2` is read-only in observer mode. It must not edit files, run fix commands,
  merge, commit, push, or send prompts into implementation workers.
- Start the observer after the implementation worker terminal(s) have been
  launched and exact tmux session names are known.
- The observer should monitor exact worker sessions and worktrees, for example
  `claude-cc4-<task-slug>` and
  `/home/zhanxp/worktrees/tg-agent-gateway/cc4`.
- The group observer result is written to
  `.omx/observers/<task-slug>.result.md`.
- By default, the report is sent to `cx2:0.0`; callers may override this with
  `--target-pane`.
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

`observe-group` example:

```bash
scripts/my_workflows.sh observe-group \
  --task <task-slug> \
  --workers cc3,cc4,cc6 \
  --target-pane cx2:0.0
```

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
- cc2 生成 group observer report 并发送给 cx2。

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

Additional CX workers:

- `cx3`-`cx5` remain the default one-shot repair scan order.
- When creating more CX workers such as `cx6`, `cx7`, or later lanes, keep the
  same worktree pattern: `/home/zhanxp/worktrees/tg-agent-gateway/<cxN>`.
- Start every new CX worker through `launch_codex_worker_terminal.sh`; do not
  create custom launch snippets that bypass app-server preflight, WSL proxy
  injection, model defaults, or the live TUI check.
- Default CX worker runtime is
  `model=${OMX_DEFAULT_CX_MODEL:-gpt-5.3-codex-spark}` and
  `reasoning_effort=${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}`.
- If a CX worker opens but stays on `Working` or `Reconnecting`, first inspect
  proxy propagation inside the worker process before changing model policy.

Selection rules:

- Choose the first worker that is clean, idle, and not blocked by existing `tmux` worker session.
- Use the unified availability helper for CX workers too; active DB rows,
  `codex-<cxN>-*` sessions, and pane cwd hits inside a CX worktree are busy.
- If the user names a specific `cxN`, use that worker only if it is clean, idle, and can be started in a long-lived visible Codex terminal; otherwise report it unavailable instead of falling back to headless execution.
- Never run multiple repair workers in parallel.
- Keep the repaired worker command consistent:
  - `model`: `${OMX_DEFAULT_CX_MODEL:-gpt-5.3-codex-spark}`
  - `model_reasoning_effort`: `${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}`

Repair worker launch pattern (visible by default):

```bash
/home/zhanxp/projects/myagent/skills/skills-local/my-workflows/scripts/launch_codex_worker_terminal.sh \
  --worktree /home/zhanxp/worktrees/tg-agent-gateway/<cxN> \
  --task-slug <cxN>-<task-slug>-repair \
  --prompt-file /home/zhanxp/projects/tg-agent-gateway/.omx/codex-handoffs/<cxN>-<task-slug>-repair.md \
  --title <cxN> \
  --model "${OMX_DEFAULT_CX_MODEL:-gpt-5.3-codex-spark}" \
  --reasoning-effort "${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}"
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

