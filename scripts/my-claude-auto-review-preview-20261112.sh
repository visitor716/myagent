#!/usr/bin/env bash
set -uo pipefail
cd /home/zhanxp/worktrees/tg-agent-gateway/cc5 || exit 1
printf 'Starting headless Claude auto-review-preview-20261112\n'
claude --permission-mode auto --print --verbose --output-format stream-json < /home/zhanxp/projects/tg-agent-gateway/.omx/claude-handoffs/cc5-auto-review-preview-20261112.md > /tmp/claude-cc5-auto-review-preview-20261112.jsonl 2>&1
result=$?
printf '\nClaude exited: %s; log: /tmp/claude-cc5-auto-review-preview-20261112.jsonl\n' "$result"
exec bash --noprofile --norc
