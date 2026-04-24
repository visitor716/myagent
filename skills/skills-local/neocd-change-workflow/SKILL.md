---
name: neocd-change-workflow
description: Implement and verify code changes inside the NeoCD/offMusicPlayer repository. Use when Codex needs to add a feature, fix a bug, refactor pages/components/hooks/services, update tests, or make other repo-local code changes while following project-specific rules such as IndexedDB-first local storage, Tailwind styling, Chinese code comments, tests under /tests, no destructive deletes, and a mandatory `npx tsc --noEmit` cleanup loop.
---

# NeoCD Change Workflow

## Overview

Implement NeoCD code changes with the smallest coherent patch, preserve the repository's local-first architecture, and finish with an explicit validation loop.

## Quick Triage

- Read `AGENTS.md` and only the smallest relevant set of files before editing.
- Identify the change type early: page/component UI, player state, local storage, metadata parsing, routing, or tests.
- If the request depends on library-specific APIs or current docs for React, Vite, Tailwind, Playwright, `jsmediatags`, or similar tools, invoke `find-docs` before coding.
- If the request implies deleting files or destructive recovery, stop and ask for confirmation first.

## Repo Constraints

- Write TypeScript using 2-space indentation, single quotes, and trailing commas.
- Use Chinese comments only when a non-obvious block needs explanation.
- Keep code modular. Split logic when functions exceed 20-80 lines, components 80-250 lines, or pages 200-400 lines.
- Place tests only under `/tests` and use `*.test.tsx`.
- Prefer `rg` for file and text search.
- Respect existing user changes and avoid reverting unrelated diffs.
- Prefer IndexedDB-backed local services in `src/services/local/`; do not introduce server-side storage unless explicitly requested.
- Preserve the existing Tailwind-based styling patterns.

## Change Mapping

- For upload, cache, and storage flows, inspect `src/services/local/` first, then uploader components and any storage statistics or cleanup UI.
- For playback behavior, inspect the player UI, audio state/context, and browser audio constraints together.
- For metadata parsing, inspect the `jsmediatags` integration and keep the existing Vite alias strategy intact unless the task is an intentional migration.
- For routing or page-level behavior, inspect `src/pages/` and the router before embedding logic in leaf components.
- For reusable UI, prefer extracting or extending components in `src/components/` rather than growing pages further.
- For shared behavior, prefer hooks or services over page-local business logic.

## Implementation Workflow

1. Read the relevant files and restate the expected behavior to yourself before editing.
2. Decide whether the change belongs in a page, component, hook, service, or test.
3. Make the smallest end-to-end code change that fully satisfies the request.
4. Add or update tests when behavior changes.
5. Preserve known repo/browser caveats when they apply:
   - set `crossOrigin='anonymous'` for cross-origin audio handling when required;
   - preserve the `jsmediatags` Vite alias approach unless intentionally replacing it;
   - remember that clearing site data wipes IndexedDB-backed music data.
6. Validate in this order:
   - run focused tests when relevant tests exist;
   - run `npx tsc --noEmit`;
   - if TypeScript fails, fix the first error, rerun, and repeat until clean.
7. Report what changed, what was verified, and any remaining risk or untested path.

## Validation Expectations

- Prefer targeted verification over full-suite runs unless the change is broad.
- Run Playwright when the change affects critical browser flows such as upload, playback, or offline persistence and confidence from unit tests is insufficient.
- If any command cannot be run, state exactly what was skipped and why.

## Do Not Use This Skill For

- Pure library or framework reference questions with no repo-local code change; use `find-docs`.
- General brainstorming that does not require editing the NeoCD repository.
- Release, version bump, or deployment workflows.
