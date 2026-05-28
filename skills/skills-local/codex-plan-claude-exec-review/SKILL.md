---
name: codex-plan-claude-exec-review
description: Use when the user wants Codex to create or refine a plan, hand that plan to a Claude Code worker for implementation in an isolated worktree, choose or arrange a tg-agent-gateway cc worker, then have Codex perform a read-only review of the completed Claude work, integrate accepted changes, verify, and refresh the local gateway runtime when needed. Triggers include "安排 cc", "安排cc", "把计划交给 Claude 做", "Claude 做完你 review", "Codex 规划 Claude 执行 Codex 检查", "plan to Claude execute to Codex review", and similar handoff/review workflows.
metadata:
  short-description: Select clean cc workers, launch Claude, review, verify, and refresh runtime
---

# Codex Plan -> Claude Execute -> Codex Review

Use this skill to coordinate a two-agent delivery loop where Codex owns planning and review, while Claude Code owns implementation in a worker worktree.

## Core Workflow

1. Produce or confirm a decision-complete plan before handoff.
2. Pick the Claude Code worker requested by the user, or use any configured `cc*` Claude Code worker. For `tg-agent-gateway`, use the "TG Gateway CC Worker Selection" policy below.
3. Verify the chosen worktree is clean enough for the task. In generic repos, a throwaway worktree may be acceptable; in `tg-agent-gateway`, do not invent an ad hoc fallback when `cc2`-`cc8` are unavailable.
4. Create handoff prompt file in `.omx/claude-handoffs/<task-slug>.md`.
5. Launch Claude Code worker in a new Windows Terminal with tmux (see "Automatic Terminal Launch" below).
6. Keep Claude's edits inside the worker worktree. Do not ask Claude to edit the main checkout directly.
7. After Claude reports completion, Codex reviews the worker diff read-only against the plan and test evidence.
8. If Codex finds blocking issues, summarize them into a compact fix task and hand it back to Claude Code. Repeat this fix loop up to 3 Claude attempts.
9. If Claude still cannot fix the task after 3 attempts, Codex takes over with the smallest safe fix.
10. If review passes, integrate the work into the target checkout, run final verification, refresh the local runtime when the change affects acceptance, and commit/merge when the user or repo workflow asked for end-to-end delivery. Keep the completed Claude worker tmux session open until the worker branch is either merged into `master` or explicitly discarded/cleaned; do not close it merely because Claude finished or the patch was copied into another checkout. Do not push unless explicitly asked.

## Automatic Terminal Launch

When handing off to Claude Code, this skill automatically launches a Windows Terminal window/tab for real-time observability:

- Script location: `scripts/launch_claude_worker_terminal.sh`
- Default behavior:
  - Uses `wt.exe` at `/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe`
  - Opens a new tab in the current window
  - Creates/attaches to a tmux session named `claude-<task-slug>`
  - Starts `claude --permission-mode auto`
  - Pastes the task prompt into Claude
  - Does not send `/compact` after task completion by default
  - If `--compact` is set, appends a task completion marker and sends
    `/compact` through tmux only after that marker appears

- Observation commands output to user:
  ```bash
  cd <worker-worktree>
  tmux attach -t claude-<task-slug>
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
worker and continue scanning `cc2`-`cc8`; fixed-worker requests such as
"安排 cc2" must report waiting/unavailable for that worker. Do not resend the
prompt and do not start a second task in the same `ccN`.

## TG Gateway CC Worker Selection

Use this policy whenever the target repo is `/home/zhanxp/projects/tg-agent-gateway` and the user asks to "安排 cc", "安排cc", "让 cc 做", or otherwise wants a Claude Code worker.

Default scan order:

```text
cc2 cc3 cc4 cc5 cc6 cc7 cc8
```

Selection rules:

- If the user names a specific `ccN`, use it only if it is clean and idle; otherwise report why it is unavailable and choose the next clean idle worker only when the user asked for generic cc execution.
- For generic "安排 cc" requests, scan `cc2` through `cc8` in order and pick the first worker that passes all availability checks.
- If every `cc2`-`cc8` worker is dirty, conflicted, DB-busy, or has an active incompatible tmux/Claude session, leave the task waiting. Do not default to `cc4`, do not reuse a dirty worktree, and do not create a throwaway worktree for this repo unless the user explicitly asks.
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
for cc in cc2 cc3 cc4 cc5 cc6 cc7 cc8; do
  wt="/home/zhanxp/worktrees/tg-agent-gateway/$cc"
  printf '\n== %s ==\n' "$cc"
  git -C "$wt" status --short 2>/dev/null || echo "missing worktree"
  sqlite3 /home/zhanxp/projects/tg-agent-gateway/data/gateway.sqlite \
    "select id,status,worker,recommended_agent,title from tasks where status in ('running','queued','planned','pending','processing') and (worker='$cc' or recommended_agent='$cc') order by created_at desc limit 5;" 2>/dev/null || true
done
tmux list-panes -a -F '#{session_name} #{pane_current_path} #{pane_current_command}' 2>/dev/null |
  rg '/home/zhanxp/worktrees/tg-agent-gateway/(cc2|cc3|cc4|cc5|cc6|cc7|cc8)|claude-cc[2-8]' || true
tmux list-sessions -F '#{session_name}' 2>/dev/null |
  rg '^claude-cc[2-8]-' || true
```

Stale completed-session cleanup:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3"
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3" --apply
```

Only run the `--apply` cleanup after proving each target worker branch has been
merged into `master`, or after intentionally discarding its diff and confirming
the worktree is clean. A completed Claude final report is not enough by itself.

Report the selected worker and the skip reason for earlier candidates. If no worker is available, report "waiting" with the blocking reasons instead of launching Claude.

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
8. Report the tmux attach command and continue by reviewing the worker diff
   after Claude finishes.
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

Use `--compact` only when the user explicitly wants post-task Claude context
compaction. In that opt-in mode, the launcher asks Claude to print a unique
completion marker at the end of its final report, then a background watcher
sends `/compact` after the marker appears. The launcher waits 5 seconds after
the marker before `/compact`; use `--compact-wait` only when that interval is
too short or unnecessarily long.

## Worktree Setup Checks

- Inspect `git status --short` in candidate worker worktrees before handoff; do not layer a new task on unresolved conflicts or unrelated dirty edits.
- For `tg-agent-gateway`, also inspect active DB rows and tmux panes before handoff; a clean git status does not prove the worker is idle.
- For `tg-agent-gateway`, if no `cc2`-`cc8` candidate is clean and idle, leave the task waiting instead of creating an extra worktree.
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

## Token-Efficient Handoff

- Tell Claude to summarize verification by command and result only. Do not ask Claude to include full logs, full diffs, or long terminal tails.
- If Claude needs to preserve detailed evidence, have it leave evidence in files or logs inside the worktree and mention the path briefly.
- Ask Claude to include token/usage only when the CLI exposes it directly; otherwise it must report `cc: unavailable`.
- Codex should not paste Claude's long final output into review context. Use Claude's short report only as a pointer to what to inspect.

## Claude Fix Loop

When Codex review finds a defect in Claude's work, prefer another Claude pass before spending Codex tokens on implementation.

- Create a new fix prompt from review findings, not from long logs. Include only: failing behavior, file/line or command evidence, expected correction, write scope, and focused verification.
- Keep the fix prompt compact. Use `git diff --stat`, targeted `git diff -- <path>`, and key test failure lines; do not paste whole diffs or long terminal output.
- Send the fix task to Claude in the same worker worktree unless the worktree is corrupted or conflicted.
- For Review-fail repair tasks in `tg-agent-gateway`, prefer a new repair child task that preserves the original `parentTaskId`, worker, worktree branch/path, and effective workspace. Do not open a new worker worktree or simply resend the original task unless the existing worktree is corrupted or the user explicitly asks.
- Count each Claude fix attempt that returns with unresolved blocking findings or failing required verification. After 3 failed fix attempts for the same task, Codex implements the minimal fix directly.
- After each Claude fix attempt, Codex repeats the same token-efficient review: status, diff stat, targeted diffs, focused tests.

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

## Codex Review Checklist

When Claude finishes, review before accepting:

- Confirm the worker and worktree path are the expected ones.
- Start with `git status --short` and `git diff --stat` in the worker worktree.
- Open only the necessary file diffs with `git diff -- <path>` or targeted slices. Avoid loading full repo diffs unless the stat shows a small bounded change.
- Compare implementation behavior to the Codex plan using direct diff inspection, not Claude's summary.
- Check that tests or verification commands were actually run and are relevant. Prefer rerunning focused commands over reading long captured logs.
- Independently rerun the most relevant verification when it is cheap. Treat Claude's claimed verification as evidence to check, not as final proof.
- Flag unrelated rewrites, deleted safeguards, broad refactors, untracked generated files, or hidden config/secret changes.
- Watch for module-load side effects introduced by the patch. In TypeScript repos, helpers that import global env/config modules can make unit tests fail before they execute; prefer side-effect-light helpers or explicit env setup in tests.
- For package scripts that already include a test path, do not assume `npm run <script> -- <file>` narrows the run. Use the underlying test binary directly when you need a single focused test, for example `./node_modules/.bin/vitest run tests/unit/foo.test.ts`.
- Use code-review style output: findings ordered by severity, with file and line references when available.
- If no issues are found, proceed to integration when appropriate rather than asking Claude for another report.

## Integration Rule

When the main checkout already has user or parallel-agent edits, do not apply
Claude's patch blindly. Read the current main files, then merge only Claude's
intended behavior into that current version. Preserve unrelated main-checkout
changes and rerun the relevant verification in the main checkout.

If you apply an accepted worker patch into the main checkout but do not commit
it in the same turn, record the source worker, changed main files, backup patch
path if any, and tmux session name in the final report. The next `merge` should
use the `worktree-merge` Accepted Patch Lane so the main patch is committed,
the duplicate worker diff is backed up/cleaned, and the worker tmux session is
closed only after final disposition.

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

For `/home/zhanxp/projects/tg-agent-gateway`, Codex owns the post-integration
runtime refresh after accepted changes. Do not make the user restart the server
for ordinary validation.

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
- After restart, report that the user can reopen the Telegram WebApp for
  acceptance and mention any runtime log errors if startup did not look clean.

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

- Codex planning and review can happen in the main checkout; Claude implementation must happen in the selected worker worktree.
- Do not push unless the user explicitly asks.
- If the top-level task asks for end-to-end delivery, then a passing Claude implementation should be integrated into the target checkout and committed according to repo rules. If commit/merge authority is unclear, report "ready to merge" instead.
- Prefer `git apply` or a normal branch merge only after checking `git status --short`, `git diff --stat`, and final verification in the target checkout. Never merge unrelated dirty worktree changes.
- Do not silently fix Claude's implementation during the review phase; first identify findings and use the Claude fix loop. If Claude fails 3 fix attempts, Codex may take over after documenting the finding and keep the fix minimal.
- If the user provides only a plan and asks for handoff, generate the Claude prompt. If the user provides Claude completion output, start review.
