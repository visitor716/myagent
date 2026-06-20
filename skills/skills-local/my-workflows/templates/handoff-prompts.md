## Handoff Prompt File

Before launching the terminal:

- Create `.omx/claude-handoffs/` or `.omx/codex-handoffs/` if needed.
- Write Claude prompts to `.omx/claude-handoffs/<task-slug>.md` and Codex
  prompts to `.omx/codex-handoffs/<task-slug>.md`.
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

### CX Repair Prompt Template

Use this when `cc` failed and a `cx` worker is taking over:

```text
请修复上一轮实现中的问题，只在当前 worker worktree 修改，不要改主仓。

失败摘要：
- [cc 的具体失败原因，含验证命令和失败结果]

目标范围：
- [允许改动文件/目录范围]

验证要求：
- [required commands]

禁止事项：
- 不改命令语义 / callback_data / 权限边界
- 不改无关文件
```

