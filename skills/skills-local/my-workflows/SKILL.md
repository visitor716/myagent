---
name: my-workflows
description: Use when tg-agent-gateway delivery should follow cx1 plan -> cx2 orchestrate -> worker execute -> observer report -> cx2 review -> master integrate/push, or when the user wants a Codex plan handed to Claude/Codex workers with observer coverage and a cx2 review gate. Triggers include "安排 cc", "安排cc", "把计划交给 Claude 做", "Claude 做完你 review", "Codex 规划 Claude 执行 Codex 检查", "plan to Claude execute to Codex review", "给 master 发任务", and similar handoff/review/master-integration workflows.
metadata:
  short-description: cx1 plan, cx2 orchestrate/review, workers execute, master integrates
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-workflows` once near the start; if it fails, continue.

# My Workflows

Use this skill to coordinate the `tg-agent-gateway` delivery loop:

`cx1 plan -> cx2 orchestrate -> worker execute -> cc2 observe -> cx2 review -> master integrate/release/push when requested`

## Core Contract

- `cx1` is plan-only: requirements, decomposition, acceptance criteria, and handoff docs. It does not implement, merge, or push business changes.
- `cx2` orchestrates execution and performs the review gate. It does not implement worker fixes, merge to master, commit, or push.
- Workers implement only inside their assigned worktree/branch and stay inside the assigned scope.
- `cc2` is the default read-only observer when clean and idle; absence of `cc2` is reported as an observer gap, not a reason to block implementation.
- `master` integrates only a candidate that passed `cx2` review, verifies in the main repo, refreshes runtime/release state when applicable, and pushes only when requested or explicitly included.

Read `references/core-contract.md` when you need the full role contract, artifact directory rules, or the detailed master-handoff policy after `cx2` PASS.

## Default Flow

1. Confirm or produce a decision-complete `cx1` plan.
2. Have `cx2` decide serial vs parallel execution and write file-backed handoff prompts.
3. Select clean, idle worker(s), defaulting implementation to `cc3`-`cc10` and observer to `cc2`.
4. Launch visible worker terminal sessions with the repo helper scripts; verify real task start by observing `Working`, tool output, or first command output.
5. Collect observer/worker output and review candidate diffs read-only against the `cx1` plan.
6. On `REVIEW: PASS`, dispatch a master integration task automatically unless the user explicitly asked for review-only output.
7. On fail, route to the next allowed repair worker or report the blocker; do not silently fix the worker diff in `cx2`.

## Reference Loading

Load only the file needed for the active lane:

- `references/worker-dispatch.md`: serial/parallel choice, fallback orchestration, worker availability, `cc2` observer policy, selected-worker handoff, and terminal launch script usage.
- `templates/handoff-prompts.md`: handoff prompt file contract and the worker/CX repair prompt templates.
- `references/review-integration.md`: `cx2` review gate, worktree setup checks, token-efficient handoff, Claude fix loop, review checklist, master integration lane, worker tmux close gate, and runtime refresh.
- `references/reporting-rules.md`: review commands, token reporting, and standing rules.

Use related specialized skills when they fit better than loading the full reference:

- `my-worktree-review` for read-only branch/worktree review gates.
- `my-worktree-merge-master` for accepted master integration, release, push/sync, and completed worker cleanup.
- `my-codex-task-queue` when dispatching a file-backed prompt into an existing Codex pane.
- `my-tmux-manager` when inspecting or controlling tmux panes.

## Non-Negotiables

- Do not reuse dirty or busy workers.
- Do not merge or push a diff that has not passed `cx2` review.
- Do not close worker tmux panes until the candidate is merged to `master` or explicitly discarded and the worktree is clean.
- Do not use the WebApp/bridge `@master ...` path for master integration work; use an existing main-repo master Codex pane or the file-backed queue lane described in `references/core-contract.md`.
- If the user says `merge`, `合并`, or `发版` for accepted worker work, continue the local master integration/release lane without asking for separate restart or `/app` confirmation.
- If the user says `push`, finish the push/sync lane only after master verification and without force-pushing or overwriting dirty/diverged refs.

## Reporting

For coding or integration work, final reports should include:

- Changed files
- Summary
- Verification
- Risks
- Next step

For review gates, lead with PASS/FAIL per branch and cite blocking findings before summaries.
