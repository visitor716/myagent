# Codex Operating Memory

Last reviewed: 2026-05-25

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
- Browser tasks must attach to the dedicated Windows Chrome agent profile
  through:
  `skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh`
- The canonical browser state is Windows Chrome with
  `--remote-debugging-port=9222`,
  `--user-data-dir=C:\chrome-wsl-automation`, and
  `--profile-directory=Default`.
- Preserve that profile's cookies, LocalStorage, SessionStorage, extensions,
  site permissions, open tabs, and login state. Do not use temporary
  user-data-dir, incognito, guest, bundled Chromium, WSL/Linux browser, or
  fresh Playwright profiles for normal browser automation.
- Never clear login state or site storage for `work.weixin.qq.com`,
  `weixin.qq.com`, or `qq.com`. If WeCom/WeChat login expires, refresh or ask
  the user to scan again; do not delete or reset the profile.
- If the dedicated Windows CDP endpoint is unavailable, stop with diagnostics.
  Do not fall back to a fresh WSL/Linux Playwright browser.

## OA WeCom Login

- For the user's DR Laser OA login, use the OA-hosted WeCom QR login route under
  `http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine?...`.
- Do not confuse this OA login QR with the separate WeCom admin console at
  `https://work.weixin.qq.com/wework_admin/loginpage_wx?from=myhome`.
- Treat `em_auth_code` and `_key` query values in pasted OA login URLs as
  transient login/session parameters. Preserve exact values only in private
  local memory when the user explicitly asks.

## Long-Term Memory

- Source-of-truth memory files live in
  `/home/zhanxp/projects/myagent/docs/agent-memory/`.
- Runtime Codex memory should include or link
  `/home/zhanxp/projects/myagent/docs/agent-memory/codex-operating-memory.md`.
- Treat `/home/zhanxp/projects/myagent` as the durable archive for the user's
  AI learning and AI usage on this machine: reusable setup, workflow memory,
  skills, automation, and repeated operating patterns should be stored here
  instead of living only in chat history.
- Update `open-loops.md` when work is paused, context is likely to compact, or
  a follow-up is discovered but not completed.
- Update `decisions.md` when a choice is made that future agents might otherwise
  revisit.

## Efficient Codex Workflow

- Use persistent project memory for decisions, preferences, blockers, and
  follow-ups that should survive across threads.
- Convert recurring workflows into skills under `skills/skills-local/` once the
  workflow has repeated or is likely to repeat.
- For goals, state the verifier up front. Good verifiers include tests,
  validation commands, reproducible bug cases, benchmark checks, or a short
  acceptance matrix.
- Treat user steering as a live redirect of the current task and user queueing
  as follow-up work to handle after the current verified step.
- Keep artifacts reviewable in the workspace when possible: Markdown reports,
  generated tables, scripts, index files, and validation logs are easier to
  resume than chat-only state.

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

## Startup MCP Policy

- Do not add Chrome DevTools or Context7 MCP startup blocks to Codex by default.
- Under WSL, runtime MCP entries that launch through `cmd /c npx` are expected
  to be unsupported or noisy unless explicitly installed for a specific task.
- `configs/sync.sh codex-full-auto` and `configs/sync.sh codex-autonomy` should
  keep pruning known unsupported startup MCP tables from Codex config.
