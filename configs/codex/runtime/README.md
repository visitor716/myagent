# Codex Runtime Backup

Generated: 2026-05-23T12:51:48+08:00
Source: /home/zhanxp/.codex
Target: /home/zhanxp/projects/myagent/configs/codex/runtime

## Included

- AGENTS.md
- config.toml
- hooks.json
- hooks.json.omx-native-hooks.bak, if present
- version.json
- agents/
- prompts/
- rules/
- memories/ (symlinks dereferenced)
- skills/ (runtime symlinks preserved)

## Excluded

- auth.json
- history.jsonl
- log/ and logs_*.sqlite*
- sessions/
- shell_snapshots/
- state_*.sqlite*
- cache/, tmp/, .tmp/
- expired OAuth authorize URL allow-rules in rules/default.rules

These excluded files are runtime state or likely to contain secrets, tokens,
conversation history, or high-churn local telemetry.
