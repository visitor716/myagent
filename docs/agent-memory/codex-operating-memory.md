# Codex Operating Memory

Last reviewed: 2026-05-23

## Autonomy

- The user explicitly trusts Codex to manage local work autonomously.
- Keep Codex's default local mode high-autonomy: `approval_policy = "never"`
  and `sandbox_mode = "danger-full-access"` unless the user explicitly asks to
  reduce privileges.
- Within higher-priority safety rules, proceed with reversible local
  configuration, scripts, repo edits, diagnostics, and verification without
  asking for confirmation.

## Browser Routing

- For browser work from WSL, use the `wsl-windows-chrome` skill first.
- Do not add or use Chrome/Browser MCP for normal browser automation unless the
  user explicitly reverses this preference.
- Browser tasks should attach to the dedicated Windows Chrome/Edge automation
  profile through:
  `skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh`
- If the dedicated Windows CDP endpoint is unavailable, stop with diagnostics.
  Do not fall back to a fresh WSL/Linux Playwright browser.

## Long-Term Memory

- Source-of-truth memory files live in
  `/home/zhanxp/projects/myagent/docs/agent-memory/`.
- Runtime Codex memory should include or link
  `/home/zhanxp/projects/myagent/docs/agent-memory/codex-operating-memory.md`.
- Update `open-loops.md` when work is paused, context is likely to compact, or
  a follow-up is discovered but not completed.
- Update `decisions.md` when a choice is made that future agents might otherwise
  revisit.

## Heartbeat

- `scripts/codex_heartbeat.py` produces the latest local status in
  `docs/agent-memory/heartbeat.md`.
- The user prefers an automatic heartbeat loop. A user-level systemd timer may
  run it every 30 minutes on this machine.
- Heartbeat checks should remain non-invasive: collect status, do not mutate
  project code, do not launch fresh browsers, and do not enable MCP.

## Model And Effort

- Default Codex config may use strong reasoning for autonomous work.
- For quick local checks, prefer explicit fast aliases rather than reducing the
  default autonomy profile globally.
