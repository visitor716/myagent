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
   and creates handoff prompt files under `.omx/claude-handoffs/` for Claude
   workers or `.omx/codex-handoffs/` for Codex workers.
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
   scope, then automatically sends the master integration task using the
   "Master Handoff After cx2 PASS" lane unless the user explicitly asked for
   review-only output. `cx2` does not merge or push.
13. `master` integrates only candidates that passed `cx2` review, runs final
   verification, applies runtime refresh when applicable, sends the `/app`
   release notification, and pushes only when the user asked or the workflow
   explicitly includes push.
14. If review fails at any stage, try the next `cx3/cx4/cx5` worker once; do
   not fallback to another `cc` attempt.
15. Keep the completed worker tmux session open until the branch is merged into
   `master` or explicitly discarded/cleaned; do not close it merely because a
   worker finished or the patch was copied elsewhere.

## Artifact Directory Contract

- Claude worker and observer prompts go under `.omx/claude-handoffs/`.
- Codex repair/review prompts go under `.omx/codex-handoffs/`.
- Worker/observer readable result reports go under `.omx/observers/`.
- Codex queue run logs go under `.omx/codex-task-queue/logs/`.
- `/home/zhanxp/projects/tg-agent-gateway/plans` is only for readable plan
  documents. Do not write raw terminal logs, unreadable traces, long tails, or
  launcher noise there.

## Master Handoff After cx2 PASS

Use this when the user says `给master发任务`, `交给master`, `master集成`,
or after `cx2` reports a `REVIEW: PASS` candidate.

- Do not use the WebApp/bridge `@master ...` new-task path for integration
  work. `@master` is a guarded `master_admin` surface and non-whitelisted
  integration prompts are rejected; the virtual `master` worker is plan-only.
- Prefer the live main-repo master Codex pane whenever it has no active agent
  output, especially `gateway:0.0` in `/home/zhanxp/projects/tg-agent-gateway`.
  Stale typed text or old scrollback is not a reason to open a new master pane:
  send `C-u`, then `/clear`, verify there is still no active output, paste the
  task, and submit it. If the pane is in Plan mode or shows an unresolved
  confirmation prompt after clear, report that specific blocker instead of
  opening a new pane silently.
- If the user explicitly says to use an already-open master terminal or not to
  open a new terminal, do not fall back to creating a fresh session. Re-list
  tmux panes and use an existing Codex pane whose cwd is
  `/home/zhanxp/projects/tg-agent-gateway`; the session name may be `gateway`
  or another live main-repo pane, not necessarily `codex-master-*`. If no
  usable opened pane exists, report blocked instead of opening a terminal.
- Create a fresh visible master Codex session only when no existing main-repo
  pane is usable, or the existing pane is actively working and the user did not
  prohibit opening a new terminal. Do not create a new master just because the
  current pane has old input that can be cleared.
- Prefer a file-backed handoff under `.omx/codex-handoffs/`, then paste and
  submit a short prompt that tells master to read that file. Do not paste a
  long integration brief directly into Codex TUI unless there is no file-backed
  path.
- Use `my-codex-task-queue` with `--cwd /home/zhanxp/projects/tg-agent-gateway`
  to enqueue and dispatch the integration prompt to that master session when
  not explicitly told to paste into a specific pane. Verify dispatch by looking
  for actual work, such as `Working`, `Ran`, or the first tool result;
  `[Pasted Content ...]` alone is not submitted work.
- If the dispatch target disappears after `codexq next`, re-enumerate existing
  main-repo Codex panes before retrying. Do not keep creating duplicate queue
  entries blindly; inspect `.omx/codex-task-queue/running/` and reuse or
  requeue the same handoff when it clearly never started. Use `--force-next`
  only for this manual recovery case, after explaining the stale running task.
- After dispatching, inspect the pane for split input. If Codex is `Working` or
  showing tool output, stop sending keys immediately even if old pasted text is
  visible in scrollback. If the prompt tail remains at the composer with
  `tab to queue message`, send `Tab` once so the tail becomes a queued
  follow-up for the same task. If the pane only shows `[Pasted Content ...]`,
  send one `Enter` and re-check; if a `Create a plan?` nudge or other composer
  UI still appears, clear the input and send only a short file-reference prompt.
  Do not keep resending or stacking long prompts.
- Master handoff prompts must name the accepted worker/worktree, exact file
  scope, verification evidence, excluded dirty state, and whether push is
  requested. When only a worker dirty diff was accepted, tell master to apply
  that file-scoped patch instead of merging the whole branch history.

