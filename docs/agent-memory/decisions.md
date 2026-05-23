# Decisions

Last reviewed: 2026-05-23

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
