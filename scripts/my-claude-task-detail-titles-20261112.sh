#!/usr/bin/env bash
set -uo pipefail
cd /home/zhanxp/worktrees/tg-agent-gateway/cc4 || exit 1
printf 'Starting headless Claude task-detail-titles-20261112\n'
claude --permission-mode auto --print --verbose --output-format stream-json < /home/zhanxp/projects/tg-agent-gateway/.omx/claude-handoffs/cc4-task-detail-titles-20261112.md > /tmp/claude-cc4-task-detail-titles-20261112.jsonl 2>&1
result=$?
printf '\nClaude exited: %s; log: /tmp/claude-cc4-task-detail-titles-20261112.jsonl\n' "$result"
exec bash --noprofile --norc
