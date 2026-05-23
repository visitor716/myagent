#!/usr/bin/env bash
set -u

project_dir="${1:-/home/zhanxp/projects/tg-agent-gateway}"
session_name="${TG_GATEWAY_TMUX_SESSION:-tg-agent-gateway}"

cd "$project_dir" || {
  echo "cannot cd to $project_dir" >&2
  exit 1
}

echo "== repo =="
pwd
git status --short

echo
echo "== shell proxy env =="
env | grep -E '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy|ALL_PROXY|all_proxy)=' || true

echo
echo "== tmux session =="
tmux has-session -t "$session_name" 2>/dev/null && echo "tmux:$session_name exists" || echo "tmux:$session_name missing"

echo
echo "== gateway process =="
pgrep -af 'node dist/index.js|tsx src/index.ts' || true

pid="$(pgrep -f 'node dist/index.js|tsx src/index.ts' | head -n1 || true)"
if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
  echo
  echo "== gateway proxy env =="
  tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy|ALL_PROXY|all_proxy)=' || true
fi

echo
echo "== recent runtime log signals =="
if [ -f logs/runtime/gateway.log ]; then
  tail -n 160 logs/runtime/gateway.log | grep -E 'Starting Telegram bot|Telegram bot is running|Gateway started successfully|Using proxy|setMyCommands|menu button|Fatal startup error|network timeout|409: Conflict|commands configured|default menu button configured' || true
else
  echo "logs/runtime/gateway.log missing"
fi

echo
echo "== tmux pane tail =="
tmux capture-pane -pt "$session_name" -S -60 2>/dev/null || true
