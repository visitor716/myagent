#!/usr/bin/env bash
set -u

project_dir="${1:-${TG_GATEWAY_PROJECT_DIR:-/home/zhanxp/projects/tg-agent-gateway}}"
session_name="${TG_GATEWAY_TMUX_SESSION:-tg-agent-gateway}"

cd "$project_dir" || {
  echo "cannot cd to $project_dir" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

section "repo"
pwd
git branch --show-current 2>/dev/null || true
git status --short

section "shell proxy env"
env | grep -E '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy|ALL_PROXY|all_proxy)=' || true

section "tmux sessions"
tmux has-session -t "$session_name" 2>/dev/null && echo "tmux:$session_name exists" || echo "tmux:$session_name missing"
tmux has-session -t tg-webapp-tunnel 2>/dev/null && echo "tmux:tg-webapp-tunnel exists" || echo "tmux:tg-webapp-tunnel missing"
tmux has-session -t tg-webapp-url-monitor 2>/dev/null && echo "tmux:tg-webapp-url-monitor exists" || echo "tmux:tg-webapp-url-monitor missing"

section "gateway process"
pgrep -af 'node dist/index.js|tsx src/index.ts|tg-agent-gateway' | grep -Ev 'grep|rg|claude' || true

pid="$(pgrep -f 'node dist/index.js|tsx src/index.ts' | head -n1 || true)"
if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
  section "gateway proxy env"
  tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(HTTPS_PROXY|HTTP_PROXY|NO_PROXY|https_proxy|http_proxy|no_proxy|ALL_PROXY|all_proxy)=' || true
fi

section "webapp env"
if [ -f .env ]; then
  grep -E '^(TG_WEBAPP_URL|WEBAPP_PORT)=' .env || true
else
  echo ".env missing"
fi

section "local health"
port="$(grep -E '^WEBAPP_PORT=' .env 2>/dev/null | tail -n1 | cut -d= -f2-)"
port="${port:-3000}"
curl -sS -m 8 "http://127.0.0.1:${port}/health" || true

section "url monitor status"
if [ -f scripts/monitor-webapp-url.sh ]; then
  bash scripts/monitor-webapp-url.sh --status || true
else
  echo "scripts/monitor-webapp-url.sh missing"
fi

section "recent runtime log signals"
if [ -f logs/runtime/gateway.log ]; then
  tail -n 180 logs/runtime/gateway.log | grep -E 'Starting Telegram bot|Telegram bot is running|Gateway started successfully|Using proxy|setMyCommands|menu button|Fatal startup error|network timeout|409: Conflict|commands configured|default menu button configured|TG_WEBAPP_URL|Notified' || true
else
  echo "logs/runtime/gateway.log missing"
fi

section "gateway tmux pane tail"
tmux capture-pane -pt "$session_name" -S -80 2>/dev/null || true

section "tunnel tmux pane tail"
tmux capture-pane -pt tg-webapp-tunnel -S -80 2>/dev/null || true
