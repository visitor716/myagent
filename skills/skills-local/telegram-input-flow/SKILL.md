---
name: telegram-input-flow
description: Implement mobile-friendly Telegram Bot multi-step text and task execution flows. Use when Codex needs to convert button-driven Telegram interactions into "tap button, prompt for text, next message creates/updates an entity" flows, or when adding awaiting-input session state, /cancel handling, callback_query cleanup, Running cards, async task completion/failure reports, success action buttons, and tests for Telegraf/Telegram bot UX.
---

# Telegram Input Flow

## Purpose

Use this skill to make Telegram Bot workflows usable on mobile: button tap enters a short-lived input state, the bot prompts for plain text, the next text message performs the action, and the user receives clear next-step buttons. For task execution flows, the user must also receive a proactive completion or failure report after any Running card.

Keep the change scoped. Preserve existing advanced slash commands and runner/execution logic unless the user explicitly asks to change them.

## Workflow

1. Locate the current entrypoint:
   - callback data for the button, such as `add_new_task`
   - text handlers, such as `bot.on('text')`
   - existing command handlers, such as `/plan`
   - keyboard builders and task/service helpers

2. Add a small session module when none exists:
   - Use an in-memory `Map` unless the project already has a suitable session/state mechanism.
   - Key by `chatId:userId` to avoid cross-chat confusion.
   - Store a specific state name such as `awaiting_task_input`, plus any defaults needed to create the entity.
   - Provide `set...`, `get...`, `clear...`, and test-only `clearAll...` helpers.

3. Add a small handler module:
   - Export prompt/error constants.
   - Normalize input with `trim()` while preserving the full user content after trimming outer whitespace.
   - Treat `/cancel` as cancellation.
   - Reject empty or whitespace-only input.
   - Generate a short title/summary from the first 20-30 user-visible characters.
   - Create the entity with safe defaults.
   - Format the success message and next-step inline keyboard.

4. Wire the callback:
   - Ensure every `callback_query` is answered via `answerCallbackQuery`/`answerCbQuery`.
   - On the "add/new" callback, clear any old task draft/input state, set the awaiting-input session, and reply:

```text
请输入任务需求：
发送 /cancel 可取消。
```

5. Wire text handling before generic text fallbacks:
   - If awaiting input and text is `/cancel`, clear state and return to the relevant list/menu.
   - If text is empty, keep the awaiting state and reply:

```text
任务需求不能为空，请重新输入，或发送 /cancel 取消。
```

   - If text is valid, create the entity, clear state, and show the success message plus next-step buttons.
   - If creation fails, reply with a readable error; do not fail silently.

6. Wire async task execution completion:
   - When a handler starts a task and receives `{ task, execution }`, send the Running card first, then attach a non-blocking completion reporter to `execution`.
   - Do not rely on task-manager status updates, logs, or task-pool state alone; those are not user-visible Telegram notifications.
   - Reuse or create a single helper such as `sendTaskCompletionReportWhenDone(ctx, execution, meta)` so text entry, buttons, and quick commands share the same completion/failure formatting.
   - On resolved execution, send the existing success/failure summary with task id, worker, terminal output/log fallback, and `/log <taskId>`.
   - On rejected execution, log structured metadata and send a short failure message with safe Telegram send/reply handling.
   - Avoid blocking the original handler until the runner finishes unless the existing UX deliberately waits.

7. Clean stale state on other buttons:
   - At the start of the central callback router, clear the awaiting-input state for that `chatId:userId`.
   - Then let the clicked button proceed normally.
   - This prevents a later plain text message from being misinterpreted as stale input.

8. Preserve advanced entrypoints:
   - Do not remove existing slash commands such as `/plan`.
   - Keep existing advanced parsing tests or add a regression test proving the command still parses.

## Success Message Pattern

Use a concise confirmation with identifiers and state:

```text
✅ 已添加到任务池

任务 ID：<id>
标题：<title>
状态：planned
项目：<project>

请选择下一步：
```

Typical buttons:

- `🤖 选择 Worker 执行` -> existing worker selection/reassignment flow
- `📋 返回任务池` -> existing list flow
- `✏️ 编辑任务` -> existing edit flow, or a clear "暂未实现" placeholder
- `❌ 删除任务` -> existing delete/confirm-delete flow

## Implementation Rules

- Prefer adding `src/telegram/handlers/<name>Handler.ts` and `src/telegram/session/<name>Session.ts` over expanding a large manager bot file.
- Keep manager bot edits to imports, callback routing, text routing, and small glue functions.
- Reuse existing service functions for persistence. Do not duplicate database writes.
- Do not change runner, worktree, lock, or execution behavior for an input UX task.
- Default fields should come from current user/bot config when available, then environment defaults, then a safe project-local fallback.
- For task-pool creation where worker is intentionally chosen later, use an empty worker only if the existing schema/service supports it; otherwise use the configured default and make the UI clear.
- Wrap optional side effects such as note syncing in `try/catch` so the main task creation does not appear to fail after persistence has succeeded.
- Any path that sends a Running task card must have a matching completion/failure notification path, including plain text auto-dispatch, quick commands, callback buttons, and retry flows.
- Prefer one shared completion-report helper over duplicating `execution.then(...)` formatting in each handler.

## Test Checklist

Add focused tests for the new handler/session logic. Prefer unit tests unless the project already has bot integration harnesses.

Cover:

- Button callback enters `awaiting_*_input` state.
- Normal text creates the expected entity.
- Created entity has the required default status and fields.
- `/cancel` clears state and does not create anything.
- Empty text does not create anything and keeps the input state.
- Success response includes the entity ID, title/status/project, and next-step buttons.
- Existing advanced slash command still works.
- Async task dispatch sends a Running card and then sends a completion report when `execution` resolves.
- Quick command and callback-triggered tasks also attach the completion reporter.
- Rejected execution promises log the error and send a failure notification instead of failing silently.

Run the project’s standard verification commands after changes, commonly:

```bash
npm run type-check
npm run test
npm run build
```
