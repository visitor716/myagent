---
name: my-project-verification
description: Run or choose the right verification commands for tg-agent-gateway and nearby Node/TypeScript workspaces. Use when the user asks for lint, typecheck, type errors, tests, unit tests, Vitest, build verification, webapp build, npm verify, or asks what checks prove a change. Prefer project package scripts over stale imported generic commands.
metadata:
  short-description: Run repo-appropriate verification checks
---

# Project Verification

Use this skill to choose and run repository-appropriate verification. Prefer the current repo's `package.json` scripts and `AGENTS.md` over generic npm, ESLint, or Vitest habits.

## tg-agent-gateway Defaults

From `/home/zhanxp/projects/tg-agent-gateway` or any of its worktrees:

- Backend TypeScript check: `npm run type-check`
- Backend build: `npm run build`
- Full backend verification: `npm run verify`
- Unit tests: `npm run test:unit`
- WebApp build: `npm run webapp:build`

Use these by change shape:

| Change shape | Verification |
| --- | --- |
| Backend/service/runner/config change | `npm run type-check && npm run build` or `npm run verify` |
| Unit-test logic or behavior with tests | `npm run test:unit` plus type/build checks when code changed |
| WebApp/frontend change | `npm run webapp:build` |
| Cross-cutting or release-bound change | `npm run verify`, then targeted tests/builds affected by the change |
| Docs-only or skill-only change | syntax/readability checks; repo build is usually unnecessary unless scripts changed |

## Command Selection

1. Inspect `package.json` before guessing command names.
2. Prefer package scripts over direct `npx` calls when a script exists.
3. Do not run formatters or linters in write/fix mode unless the user explicitly asks.
4. If a command fails because required environment is missing, report the exact missing variable and whether the failure blocks the requested claim.
5. If tests are targeted, name the exact file or pattern and explain why broader tests were not needed.

## Reporting

Report verification with:

- command
- pass/fail result
- important failure lines if any
- residual risk or untested path

Do not claim completion from command exit alone; read enough output to verify the command checked the intended target.
