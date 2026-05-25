---
name: codex-plan-claude-exec-review
description: Use when the user wants Codex to create or refine a plan, hand that plan to a Claude Code worker for implementation in an isolated worktree, then have Codex perform a read-only review of the completed Claude work. Triggers include "把计划交给 Claude 做", "Claude 做完你 review", "Codex 规划 Claude 执行 Codex 检查", "plan -> Claude execute -> Codex review", and similar handoff/review workflows.
metadata:
  short-description: Hand Codex plans to Claude Code and review the result
---

# Codex Plan -> Claude Execute -> Codex Review

Use this skill to coordinate a two-agent delivery loop where Codex owns planning and review, while Claude Code owns implementation in a worker worktree.

## Core Workflow

1. Produce or confirm a decision-complete plan before handoff.
2. Pick the Claude Code worker requested by the user, or use a configured Claude Code worker such as `cc1`, `cc2`, `cc3`, or `cc4`.
3. Verify the chosen worktree is clean enough for the task. If existing worker worktrees are dirty or conflicted, create a throwaway worktree from the intended base ref instead of reusing them.
4. Create handoff prompt file in `.omx/claude-handoffs/<task-slug>.md`.
5. Launch Claude Code worker in a new Windows Terminal with tmux (see "Automatic Terminal Launch" below).
6. Keep Claude's edits inside the worker worktree. Do not ask Claude to edit the main checkout directly.
7. After Claude reports completion, Codex reviews the worker diff read-only against the plan and test evidence.
8. If Codex finds blocking issues, summarize them into a compact fix task and hand it back to Claude Code. Repeat this fix loop up to 3 Claude attempts.
9. If Claude still cannot fix the task after 3 attempts, Codex takes over with the smallest safe fix.
10. If review passes, integrate the work into the target checkout, run final verification, and commit/merge when the user or repo workflow asked for end-to-end delivery. Do not push unless explicitly asked.

## Automatic Terminal Launch

When handing off to Claude Code, this skill automatically launches a Windows Terminal window/tab for real-time observability:

- Script location: `scripts/launch_claude_worker_terminal.sh`
- Default behavior:
  - Uses `wt.exe` at `/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe`
  - Opens a new tab in the current window
  - Creates/attaches to a tmux session named `claude-<task-slug>`
  - Runs `claude --permission-mode auto < handoff-prompt.md`

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

## Terminal Launch Script Usage

```bash
scripts/launch_claude_worker_terminal.sh \
  --worktree <path> \
  --task-slug <slug> \
  --prompt-file <path> \
  [--terminal-mode tab|window] \
  [--dry-run] [--verbose]
```

## Worktree Setup Checks

- Inspect `git status --short` in candidate worker worktrees before handoff; do not layer a new task on unresolved conflicts or unrelated dirty edits.
- If no clean worker worktree is available, create an isolated one with `git worktree add -b wt/<task-slug> <path> HEAD` or the requested base ref. Do not commit from this temporary worktree unless explicitly asked.
- If the new worktree lacks dependencies but the main checkout has them, prefer installing normally when appropriate. For quick local verification only, a `node_modules` symlink can be excluded via the worktree's local `.git/info/exclude`; do not edit tracked ignore rules just for that symlink.
- Run one cheap baseline verification before handoff when possible, such as `npm run type-check`, so Claude does not inherit a broken worktree.

## Handoff Prompt File

Before launching the terminal:

- Create `.omx/claude-handoffs/` directory if it doesn't exist.
- Write the handoff prompt to `.omx/claude-handoffs/<task-slug>.md`.
- Generate a clean task slug from the task description (lowercase, alphanumeric + hyphens only).
- The prompt file is fed directly to `claude --permission-mode auto < prompt-file.md`.
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
- 最终回复必须简短，不要粘贴完整 diff、长日志、完整测试输出或大段终端记录。

完成后输出：
1. Changed Files
2. Summary
3. Verification
4. Risks
```

## Token-Efficient Handoff

- Tell Claude to summarize verification by command and result only. Do not ask Claude to include full logs, full diffs, or long terminal tails.
- If Claude needs to preserve detailed evidence, have it leave evidence in files or logs inside the worktree and mention the path briefly.
- Codex should not paste Claude's long final output into review context. Use Claude's short report only as a pointer to what to inspect.

## Claude Fix Loop

When Codex review finds a defect in Claude's work, prefer another Claude pass before spending Codex tokens on implementation.

- Create a new fix prompt from review findings, not from long logs. Include only: failing behavior, file/line or command evidence, expected correction, write scope, and focused verification.
- Keep the fix prompt compact. Use `git diff --stat`, targeted `git diff -- <path>`, and key test failure lines; do not paste whole diffs or long terminal output.
- Send the fix task to Claude in the same worker worktree unless the worktree is corrupted or conflicted.
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
- 最终只输出 Changed Files / Summary / Verification / Risks，不粘贴长日志或完整 diff。

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

## Review Commands

Prefer read-only commands such as:

```bash
git -C <worker-worktree> status --short
git -C <worker-worktree> diff --stat
git -C <worker-worktree> diff -- <path>
git -C <worker-worktree> log --oneline --decorate -5
```

Run tests only if they are non-destructive for the repo and needed to validate the claim. Capture the command status and key failure lines; do not read or paste full test logs unless the failure cannot be diagnosed otherwise.

## Rules

- Codex planning and review can happen in the main checkout; Claude implementation must happen in the selected worker worktree.
- Do not push unless the user explicitly asks.
- If the top-level task asks for end-to-end delivery, then a passing Claude implementation should be integrated into the target checkout and committed according to repo rules. If commit/merge authority is unclear, report "ready to merge" instead.
- Prefer `git apply` or a normal branch merge only after checking `git status --short`, `git diff --stat`, and final verification in the target checkout. Never merge unrelated dirty worktree changes.
- Do not silently fix Claude's implementation during the review phase; first identify findings and use the Claude fix loop. If Claude fails 3 fix attempts, Codex may take over after documenting the finding and keep the fix minimal.
- If the user provides only a plan and asks for handoff, generate the Claude prompt. If the user provides Claude completion output, start review.
