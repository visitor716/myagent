## CX2 Review Gate

- `cx2` review is mandatory only after repair candidate is ready.
- `cx2` is review-only. It must not implement, modify files, merge, commit, or
  push.
- `cx2` output requires clear `pass/fail`, blocking findings, verification
  evidence, and a master integration recommendation.
- On pass, `cx2` outputs only the candidate worker/branch/patch, verification
  evidence, risks, and recommended master merge scope, then immediately creates
  and dispatches the master integration task through the "Master Handoff After
  cx2 PASS" lane. Do not wait for a separate `给master发任务` prompt unless the
  user explicitly requested review-only/ready-to-merge output.
- The post-review dispatch report must include the target master pane or queue
  target, queued task id/marker when available, and whether dispatch actually
  started (`Working`, tool call, or blocker). If dispatch is blocked by no
  usable opened pane and the user prohibited new terminals, report that blocker
  while preserving the PASS candidate details.
- On fail, `cx2` routes the task to the next allowed repair worker or reports
  blocked state. It must not silently fix the worker diff itself.
- `cx2` review launch pattern (visible by default):

```bash
/home/zhanxp/projects/myagent/skills/skills-local/my-workflows/scripts/launch_codex_worker_terminal.sh \
  --worktree /home/zhanxp/worktrees/tg-agent-gateway/cx2 \
  --task-slug cx2-<task-slug>-review \
  --prompt-file /home/zhanxp/projects/tg-agent-gateway/.omx/codex-handoffs/cx2-<task-slug>-review.md \
  --title cx2 \
  --model gpt-5.5 \
  --reasoning-effort "${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}"
```

- If review fails, route to next available repair worker (`cx3/cx4/cx5` order), then stop and report if no additional worker remains.

## Worktree Setup Checks

- Inspect `git status --short` in candidate worker worktrees before handoff; do not layer a new task on unresolved conflicts or unrelated dirty edits.
- For `tg-agent-gateway`, also inspect active DB rows and tmux panes before handoff; a clean git status does not prove the worker is idle.
- For `tg-agent-gateway`, if no `cc2`-`cc10` candidate is clean and idle, leave the task waiting instead of creating an extra worktree.
- If no clean worker worktree is available, create an isolated one with `git worktree add -b wt/<task-slug> <path> HEAD` or the requested base ref. Do not commit from this temporary worktree unless explicitly asked.
- If the new worktree lacks dependencies but the main checkout has them, prefer installing normally when appropriate. For quick local verification only, a `node_modules` symlink can be excluded via the worktree's local `.git/info/exclude`; do not edit tracked ignore rules just for that symlink.
- Run one cheap baseline verification before handoff when possible, such as `npm run type-check`, so Claude does not inherit a broken worktree.

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

