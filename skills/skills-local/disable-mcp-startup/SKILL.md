---
name: my-disable-mcp-startup
description: Disable broken or unwanted MCP startup entries for Codex and Claude Code without broad config rewrites. Use when the user asks to 禁用 MCP, 不启动 MCP 工具, remove MCP startup warnings, silence chrome-devtools or context7 startup failures, avoid browser MCP, clean MCP allowlists, fix MCP entries reappearing after Codex updates, or ensure runtime and myagent config templates do not re-enable MCP on restore.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-disable-mcp-startup` once near the start; if it fails, continue.


# Disable MCP Startup

## Overview

Use this skill to remove startup-time MCP noise from Codex and Claude Code while preserving unrelated runtime configuration. The goal is not to uninstall every MCP package on the machine; it is to stop configured MCP clients from loading at agent startup and to keep repo templates from restoring them later.

## Workflow

1. Treat pasted MCP startup warnings, "禁用 MCP", or "MCP 又启动了" as confirmation to clean startup MCP noise. Do not use MCP tools while doing this cleanup.
2. Diagnose the active Codex state before editing:

```bash
codex mcp list
codex features list | rg "^(apps|enable_mcp_apps)\b"
```

   - `chrome-devtools` and `context7` in `codex mcp list` come from `[mcp_servers.*]` tables, usually in `~/.codex/config.toml`.
   - `codex_apps` does not appear as a normal MCP server; it is controlled by feature flags. Keep `features.apps = false` and verify `enable_mcp_apps` is false.
   - After a Codex update, the runtime config may regain MCP tables even while myagent templates remain clean. In that case, edit only `~/.codex/config.toml`.
   - If `codex mcp list` is already empty but startup still mentions MCP, inspect feature flags and the exact warning text before changing unrelated files.
3. Inspect the likely runtime and template files:

```bash
rg -n "mcp_servers|mcp__|MCP_TIMEOUT|chrome-devtools|context7|codex_apps|open-websearch|features|enable_mcp_apps" \
  ~/.codex/config.toml \
  ~/.claude/settings.json \
  /home/zhanxp/projects/myagent/configs/codex/config.toml \
  "/home/zhanxp/projects/myagent/configs/claude code/settings.json" \
  /home/zhanxp/projects/myagent/configs/claude-code/settings.json 2>/dev/null
```

4. Remove only MCP startup configuration and MCP permission allowlist entries:
   - Codex TOML: remove enabled `[mcp_servers.*]` blocks, including an empty parent `[mcp_servers]` table if no server tables remain. Set disabled flags only if the existing config already uses that pattern.
   - Claude JSON: remove MCP allowlist entries such as `mcp__context7`, `mcp__chrome-devtools`, and related `MCP_TIMEOUT` environment settings only when the user is fixing Claude startup warnings or the current warning points at Claude.
   - Repo templates: make the same narrow cleanup only when they still contain the startup entries or when a restore/sync path would reintroduce them.
5. Keep all unrelated provider, model, permission, browser, skill, memory, and sync settings intact.
6. Validate formats before claiming success:

```bash
python3 -m json.tool ~/.claude/settings.json >/dev/null
python3 -m json.tool "/home/zhanxp/projects/myagent/configs/claude code/settings.json" >/dev/null
python3 - <<'PY'
import tomllib
for path in [
    "/home/zhanxp/.codex/config.toml",
    "/home/zhanxp/projects/myagent/configs/codex/config.toml",
]:
    with open(path, "rb") as handle:
        tomllib.load(handle)
print("toml ok")
PY
```

7. Run the repo-native validation when editing files under `configs/`:

```bash
bash /home/zhanxp/projects/myagent/configs/sync.sh validate
```

8. Confirm no startup MCP servers remain for Codex:

```bash
codex mcp list
codex features list | rg "^(apps|enable_mcp_apps)\b"
```

Expected clean result is no configured MCP servers. If the command text changes, report the exact output instead of assuming.
9. Optionally run `codex doctor` for a fuller post-check. It can exit nonzero for unrelated HTTP reachability or proxy failures; read and report the `Configuration` / `mcp` sections separately instead of treating those unrelated failures as MCP cleanup failures.

## Safety Rules

- Do not add Chrome/Browser MCP as a replacement for `wsl-windows-chrome`; the user prefers the dedicated Windows Chrome skill for browser automation.
- Do not delete credentials, auth files, sessions, history, or unrelated runtime state.
- Do not rewrite whole JSON/TOML files if a minimal structural edit can remove the MCP entries.
- Do not treat missing `jq` as a blocker; use `python3 -m json.tool` and Python `tomllib`.
- If a config path with a space exists, quote it exactly, especially `configs/claude code/settings.json`.

## Completion Report

Report the exact files changed, MCP server or allowlist names removed, validation commands run, and any remaining MCP references that were intentionally left alone because they are docs, comments, or unrelated templates.
