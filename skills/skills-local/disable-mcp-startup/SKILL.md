---
name: disable-mcp-startup
description: Disable broken or unwanted MCP startup entries for Codex and Claude Code without broad config rewrites. Use when the user asks to 禁用 MCP, 不启动 MCP 工具, remove MCP startup warnings, silence chrome-devtools or context7 startup failures, avoid browser MCP, clean MCP allowlists, or ensure runtime and myagent config templates do not re-enable MCP on restore.
---

# Disable MCP Startup

## Overview

Use this skill to remove startup-time MCP noise from Codex and Claude Code while preserving unrelated runtime configuration. The goal is not to uninstall every MCP package on the machine; it is to stop configured MCP clients from loading at agent startup and to keep repo templates from restoring them later.

## Workflow

1. Confirm the user wants MCP startup disabled or warning noise removed. Do not use MCP tools while doing this cleanup.
2. Inspect the likely runtime and template files:

```bash
rg -n "mcp_servers|mcp__|MCP_TIMEOUT|chrome-devtools|context7|open-websearch" \
  ~/.codex/config.toml \
  ~/.claude/settings.json \
  /home/zhanxp/projects/myagent/configs/codex/config.toml \
  "/home/zhanxp/projects/myagent/configs/claude code/settings.json" \
  /home/zhanxp/projects/myagent/configs/claude-code/settings.json 2>/dev/null
```

3. Remove only MCP startup configuration and MCP permission allowlist entries:
   - Codex TOML: remove enabled `[mcp_servers.*]` blocks or set them disabled only if the existing config uses that pattern.
   - Claude JSON: remove MCP allowlist entries such as `mcp__context7`, `mcp__chrome-devtools`, and related `MCP_TIMEOUT` environment settings.
   - Repo templates: make the same narrow cleanup so future restore/sync does not bring the startup noise back.
4. Keep all unrelated provider, model, permission, browser, skill, memory, and sync settings intact.
5. Validate formats before claiming success:

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

6. Run the repo-native validation when editing files under `configs/`:

```bash
bash /home/zhanxp/projects/myagent/configs/sync.sh validate
```

7. Confirm no startup MCP servers remain for Codex:

```bash
codex mcp list
```

Expected clean result is no configured MCP servers. If the command text changes, report the exact output instead of assuming.

## Safety Rules

- Do not add Chrome/Browser MCP as a replacement for `wsl-windows-chrome`; the user prefers the dedicated Windows Chrome skill for browser automation.
- Do not delete credentials, auth files, sessions, history, or unrelated runtime state.
- Do not rewrite whole JSON/TOML files if a minimal structural edit can remove the MCP entries.
- Do not treat missing `jq` as a blocker; use `python3 -m json.tool` and Python `tomllib`.
- If a config path with a space exists, quote it exactly, especially `configs/claude code/settings.json`.

## Completion Report

Report the exact files changed, MCP server or allowlist names removed, validation commands run, and any remaining MCP references that were intentionally left alone because they are docs, comments, or unrelated templates.
