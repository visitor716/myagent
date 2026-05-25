# Decisions

Last reviewed: 2026-05-25

## 2026-05-25 - Use MyAgent As The AI Work Archive

Decision: Treat `/home/zhanxp/projects/myagent` as the durable archive for
everything worth preserving from the user's AI learning and AI usage:
operating memory, reusable skills, configuration templates, workflow notes, and
local automation on this machine.

Context: The high-leverage Codex workflow depends on persistent threads,
shared memory, reusable skills, automation, and explicit goal verifiers. This
repo already stores those surfaces, so it should be the first place future
agents update durable context rather than leaving it only in chat. The broader
project scope is the user's accumulated AI-use experience, not only Codex.

Directive: Put durable preferences in `docs/agent-memory/codex-operating-memory.md`,
paused follow-ups in `docs/agent-memory/open-loops.md`, reusable workflows in
`skills/skills-local/`, and runtime template changes under `configs/`.

## 2026-05-25 - Prune Unsupported Codex Startup MCP Blocks

Decision: Keep Codex startup MCP empty by default and remove known unsupported
WSL `cmd /c npx` MCP tables during `codex-full-auto` and `codex-autonomy`.

Context: Browser automation should use `wsl-windows-chrome`, while the runtime
`chrome-devtools` and `context7` MCP entries launch through Windows `cmd` from
WSL and show as unsupported.

Directive: Do not re-add `mcp_servers.chrome-devtools` or
`mcp_servers.context7` to Codex startup config unless the user explicitly asks
for MCP for a specific task.

## 2026-05-23 - Keep Codex High-Autonomy By Default

Decision: Keep local Codex configured for no approvals and full filesystem
access on this trusted machine.

Context: The user explicitly stated they trust Codex to manage everything
automatically. This supersedes the earlier optimization suggestion to make
workspace sandboxing the default.

Directive: Do not downgrade `approval_policy = "never"` or
`sandbox_mode = "danger-full-access"` unless the user explicitly asks.

## 2026-05-23 - Browser Automation Uses WSL Windows Chrome Skill

Decision: Browser automation should use the `wsl-windows-chrome` skill, not
Chrome/Browser MCP.

Context: The user explicitly prefers the skill-based Windows Chrome attach
workflow. Current Codex MCP list is empty, and this is intentional.

Directive: Do not add Chrome DevTools MCP back to Codex config unless the user
explicitly asks for MCP.
