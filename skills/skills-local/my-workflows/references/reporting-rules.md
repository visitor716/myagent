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
