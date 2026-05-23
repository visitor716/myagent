# >>> codex full-auto defaults >>>
_codex_has_permission_flag() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--sandbox|--sandbox=*|-s|--ask-for-approval|--ask-for-approval=*|-a)
        return 0
        ;;
    esac
  done
  return 1
}

codex() {
  if _codex_has_permission_flag "$@"; then
    command codex "$@"
    return
  fi

  case "${1:-}" in
    login|logout|mcp|plugin|mcp-server|app-server|completion|sandbox|debug|apply|a|cloud|exec-server|features|help|--help|-h|--version|-V)
      command codex "$@"
      ;;
    exec|e|review|resume|fork)
      local subcommand="$1"
      shift
      command codex "$subcommand" --dangerously-bypass-approvals-and-sandbox "$@"
      ;;
    *)
      command codex --dangerously-bypass-approvals-and-sandbox "$@"
      ;;
  esac
}

code() {
  if [ "${1:-}" = "x" ]; then
    shift
    codex "$@"
  else
    command code "$@"
  fi
}

alias cyolo='command codex --dangerously-bypass-approvals-and-sandbox'
alias cfa='command codex --full-auto'
alias omxmad='omx --madmax'

cfast() {
  command codex --dangerously-bypass-approvals-and-sandbox \
    -m gpt-5.4-mini \
    -c 'model_reasoning_effort="high"' \
    "$@"
}

cdeep() {
  command codex --dangerously-bypass-approvals-and-sandbox \
    -m gpt-5.5 \
    -c 'model_reasoning_effort="xhigh"' \
    "$@"
}

cheartbeat() {
  python3 /home/zhanxp/projects/myagent/scripts/codex_heartbeat.py "$@"
}

cchrome_status() {
  bash /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --status --json "$@"
}

cchrome_attach() {
  bash /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh "$@"
}

cremote() {
  command codex remote-control --enable remote_control --enable prevent_idle_sleep "$@"
}
# <<< codex full-auto defaults <<<
