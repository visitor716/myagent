---
name: my-worktree-review
description: >
  Review tg-agent-gateway worker worktrees and all candidate branches as a cx2
  review gate.  Trigger on: review 分支 / review worker branch / review all
  branches / 审查 worktree / cx2 review gate / 能不能 merge / worker diff.
  Performs read-only branch-by-branch checks (repo/worktree/branch, diff scope,
  plans, evidence) to decide cx2 accepted/master handoff.  Never merges, pushes,
  edits, or cleans worktrees.
---

# My Worktree Review

Use this skill to perform a read-only review gate for tg-agent-gateway worker worktrees and branches.

## Scope

This skill decides whether worker branch results are safe to accept as `cx2 accepted` or hand to master for integration.

It must not:
- edit files
- commit
- merge
- push
- reset
- checkout away user work
- clean worker worktrees
- stop tmux panes
- mark tasks accepted without explicit workflow authority

## Required Inputs

Infer these from the repo when possible:
- target worktree path
- worker alias list or branch pattern
- review scope (`single`, `all`, `all-worker`)
- parent task or plan
- claimed changed files
- claimed verification commands
- review objective

If no target is clear, infer from current repo context and available task context.

When scope is `all` or `all-worker`, evaluate each candidate branch under the target worktree and provide one pass/fail entry per branch.

If multiple worktrees are available and target is ambiguous, report candidates and stop with `REVIEW: FAIL`.

## Read-Only Evidence Checklist

Run or inspect only read-only commands/sources:

- `pwd`
- `git status --short`
- `git branch --show-current`
- `git branch --list`
- `git diff --stat`
- `git diff --name-status`
- `git diff`
- `git log --oneline --decorate -n 10`
- `git worktree list --porcelain`
- task plan under `plans/`
- task log under `logs/runs/`
- task DB or exported task details when relevant
- existing test output or verification evidence

Prefer existing project scripts when present:
- `scripts/audit_worker_refs.sh`
- `scripts/audit_dirty_worktrees.sh`
- `scripts/report-worker-worktrees.sh`

Do not run expensive validation unless explicitly asked. If verification is missing, mark it as a gap.

## Review Decision Rules

Apply rules independently per branch:

Return branch `PASS` only when all are true:
- diff matches task scope
- no unrelated dirty changes are mixed in
- branch/worktree identity is clear
- claimed files match actual diff
- verification evidence is present and relevant
- no callback_data, task status semantics, workspace, permission mode, or worker alias changes unless explicitly required
- no secrets, tokens, logs, `.env`, or generated runtime artifacts are included
- master can integrate without unresolved product/architecture questions

Return branch `FAIL` when any are true:
- target branch is ambiguous
- diff contains unrelated changes
- dirty state includes unreviewed files
- validation is missing for code changes
- implementation contradicts cx1 plan or user scope
- task only changed UI text but claimed backend/runtime behavior
- runner/task semantics changed without explicit requirement
- generated files/logs/secrets are included
- merge would require manual conflict or policy decision

Manual-only gaps do not always require implementation failure. Label them clearly:
- `manual_verification_gap`
- `evidence_gap`
- `runtime_gap`

Overall skill result:
- `REVIEW: PASS` only when all audited branches are PASS
- `REVIEW: FAIL` if any branch is FAIL or scope cannot be established

## Output Format

Start with exactly one:

`REVIEW: PASS`

or

`REVIEW: FAIL`

Then output exactly this structure:

```markdown
## Summary
- One to four bullets summarizing scope and gate outcome.

## Candidates
- Worktree:
- Scope: all branches / all-worker / single branch
- Workers:

## Branch Review Matrix
- Branch:
  - Worker:
  - Task:
  - Decision:
  - Files changed:
  - In scope:
  - Out of scope:
  - Dirty/untracked state:
- Branch:
  - ...

## Aggregate Diff Scope
- Files changed:
- In scope:
- Out of scope:
- Dirty/untracked state:

## Verification Evidence
- Commands claimed:
- Evidence found:
- Missing verification:

## Risks
- List concrete risks or `None`.

## Master Integration Recommendation
- Integrate:
- Required action before master:
- Branch-by-branch recommendation:
- Suggested command/path for next reviewer:

## Next Step
- One concrete next step.
```

## tg-agent-gateway Rules

Respect repository role separation:
- `cx1` plans only.
- `cx2` reviews and orchestrates.
- `master` integrates only reviewed candidates.
- worker worktrees implement in isolation.

Never merge a worker directly from this skill.
Never clean or discard dirty worktree changes unless explicitly instructed.
