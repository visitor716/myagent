#!/usr/bin/env bash
set -euo pipefail

WT_PATH="/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe"

WORKTREE=""
TASK_SLUG=""
PROMPT_FILE=""
WORKER_TITLE=""
CODEX_BIN=""
MODEL="${OMX_DEFAULT_CX_MODEL:-gpt-5.3-codex-spark}"
REASONING_EFFORT="${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}"
DRY_RUN=0
VERBOSE=0
TERMINAL_MODE="tab"
EXEC_MODE=0
APP_SERVER_PREFLIGHT=1

usage() {
  cat <<'EOF_USAGE'
Usage:
  launch_codex_worker_terminal.sh --worktree <path> --task-slug <slug> --prompt-file <path> [options]

Options:
  --worktree <path>             Required. Path to worker worktree.
  --task-slug <slug>            Required. Short task identifier for tmux session name.
  --prompt-file <path>          Required. Path to handoff prompt file.
  --title <title>               Optional. Windows Terminal tab title. Default: worktree basename.
  --model <model>               Optional. Codex model (default: gpt-5.3-codex-spark).
  --reasoning-effort <effort>    Optional. model_reasoning_effort value (default: xhigh).
  --exec                         Run headless `codex exec` instead of interactive Codex CLI.
  --interactive                  Run interactive Codex CLI. Default.
  --no-app-server-preflight       Do not check/restart Codex app-server before launch.
  --dry-run                     Print commands without executing or writing launch files.
  --verbose                     Print verbose output.
  --terminal-mode <tab|window>  Optional. Default: tab.
  -h, --help                    Show this help.
EOF_USAGE
}

log() {
  printf '%s\n' "$*"
}

vlog() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    log "$*"
  fi
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

codex_exec_cmd_line() {
  printf "'%s' exec --dangerously-bypass-approvals-and-sandbox -C '%s' -m '%s' -c 'model_reasoning_effort=\"%s\"' --skip-git-repo-check --color never -" \
    "$CODEX_BIN" \
    "$WORKTREE" "$MODEL" "$REASONING_EFFORT"
}

codex_interactive_cmd_line() {
  printf "'%s' --dangerously-bypass-approvals-and-sandbox -C '%s' -m '%s' -c 'model_reasoning_effort=\"%s\"'" \
    "$CODEX_BIN" \
    "$WORKTREE" "$MODEL" "$REASONING_EFFORT"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)
      [[ $# -ge 2 ]] || die "--worktree requires a value"
      WORKTREE="$2"
      shift 2
      ;;
    --task-slug)
      [[ $# -ge 2 ]] || die "--task-slug requires a value"
      TASK_SLUG="$2"
      shift 2
      ;;
    --prompt-file)
      [[ $# -ge 2 ]] || die "--prompt-file requires a value"
      PROMPT_FILE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || die "--title requires a value"
      WORKER_TITLE="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires a value"
      MODEL="$2"
      shift 2
      ;;
    --reasoning-effort)
      [[ $# -ge 2 ]] || die "--reasoning-effort requires a value"
      REASONING_EFFORT="$2"
      shift 2
      ;;
    --exec)
      EXEC_MODE=1
      shift
      ;;
    --interactive)
      EXEC_MODE=0
      shift
      ;;
    --no-app-server-preflight)
      APP_SERVER_PREFLIGHT=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --terminal-mode)
      [[ $# -ge 2 ]] || die "--terminal-mode requires a value"
      TERMINAL_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$WORKTREE" ]] || die "--worktree is required"
[[ -n "$TASK_SLUG" ]] || die "--task-slug is required"
[[ -n "$PROMPT_FILE" ]] || die "--prompt-file is required"
[[ -d "$WORKTREE" ]] || die "Worktree not found: $WORKTREE"
[[ -f "$PROMPT_FILE" ]] || die "Prompt file not found: $PROMPT_FILE"
if command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
else
  CODEX_BIN="/home/zhanxp/.local/bin/codex"
fi
if [[ ! -x "$CODEX_BIN" ]]; then
  die "codex executable not found or not executable: $CODEX_BIN"
fi
case "$TERMINAL_MODE" in
  tab|window) ;;
  *) die "--terminal-mode must be tab or window" ;;
esac

if [[ -z "$WORKER_TITLE" ]]; then
  WORKER_TITLE="$(basename "$WORKTREE")"
fi

TMUX_SESSION="codex-${TASK_SLUG}"
LAUNCHER_DIR="$(dirname "$PROMPT_FILE")/../codex-launchers"
LAUNCHER_PATH="$LAUNCHER_DIR/${TASK_SLUG}.sh"
RUNNER_PATH="$LAUNCHER_DIR/${TASK_SLUG}.codex-runner.sh"
if [[ "$EXEC_MODE" -eq 1 ]]; then
  CODEX_CMD_LINE="$(codex_exec_cmd_line)"
else
  CODEX_CMD_LINE="$(codex_interactive_cmd_line)"
fi
CX_WORKER_NAME=""
if [[ "$WORKER_TITLE" =~ ^cx[0-9]+$ ]]; then
  CX_WORKER_NAME="$WORKER_TITLE"
elif [[ "$(basename "$WORKTREE")" =~ ^cx[0-9]+$ ]]; then
  CX_WORKER_NAME="$(basename "$WORKTREE")"
fi
TG_GATEWAY_CX_GUARD=0
if [[ -n "$CX_WORKER_NAME" ]]; then
  case "$WORKTREE" in
    "/home/zhanxp/worktrees/tg-agent-gateway/$CX_WORKER_NAME"|"/home/zhanxp/worktrees/tg-agent-gateway/$CX_WORKER_NAME/")
      TG_GATEWAY_CX_GUARD=1
      ;;
  esac
fi
CX_WORKER_SESSION_PATTERN=""
if [[ "$TG_GATEWAY_CX_GUARD" -eq 1 ]]; then
  CX_WORKER_SESSION_PATTERN="codex-${CX_WORKER_NAME}-*"
fi

vlog "Worktree: $WORKTREE"
vlog "Task slug: $TASK_SLUG"
vlog "Prompt file: $PROMPT_FILE"
vlog "Model: $MODEL"
vlog "Reasoning effort: $REASONING_EFFORT"
vlog "Session: $TMUX_SESSION"
vlog "Terminal mode: $TERMINAL_MODE"
vlog "Dry run: $DRY_RUN"
vlog "Exec mode: $EXEC_MODE"
vlog "App-server preflight: $APP_SERVER_PREFLIGHT"
vlog "Command: $CODEX_CMD_LINE"
vlog "CX worker name: $CX_WORKER_NAME"
vlog "TG gateway cx guard: $TG_GATEWAY_CX_GUARD"
vlog "CX worker session pattern: $CX_WORKER_SESSION_PATTERN"

render_codex_runner_script() {
  cat <<EOF_RUNNER
#!/usr/bin/env bash
set -euo pipefail

WORKTREE=$(printf '%q' "$WORKTREE")
PROMPT_FILE=$(printf '%q' "$PROMPT_FILE")
CODEX_BIN=$(printf '%q' "$CODEX_BIN")
MODEL=$(printf '%q' "$MODEL")
REASONING_EFFORT=$(printf '%q' "$REASONING_EFFORT")
APP_SERVER_PREFLIGHT=$(printf '%q' "$APP_SERVER_PREFLIGHT")

cd "\$WORKTREE"

run_maybe_timeout() {
  local duration="\$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "\$duration" "\$@"
  else
    "\$@"
  fi
}

restart_codex_app_server() {
  local reason="\$1"
  printf '[WARN] Codex app-server preflight failed: %s\n' "\$reason" >&2
  printf '[WARN] Restarting managed Codex app-server before launching worker...\n' >&2
  run_maybe_timeout 20s "\$CODEX_BIN" app-server daemon restart >&2
}

preflight_codex_app_server() {
  if [[ "\$APP_SERVER_PREFLIGHT" != "1" ]]; then
    return 0
  fi

  local version_output=""
  if ! version_output="\$(run_maybe_timeout 10s "\$CODEX_BIN" app-server daemon version 2>&1)"; then
    restart_codex_app_server "\$version_output"
    return 0
  fi

  local cli_version=""
  local app_server_version=""
  cli_version="\$(printf '%s' "\$version_output" | sed -n 's/.*"cliVersion":"\([^"]*\)".*/\1/p')"
  app_server_version="\$(printf '%s' "\$version_output" | sed -n 's/.*"appServerVersion":"\([^"]*\)".*/\1/p')"
  if [[ -n "\$cli_version" && -n "\$app_server_version" && "\$cli_version" != "\$app_server_version" ]]; then
    restart_codex_app_server "cliVersion=\$cli_version appServerVersion=\$app_server_version"
  fi
}

load_wsl_proxy_env() {
  if [[ -n "\${https_proxy:-}" || -n "\${HTTPS_PROXY:-}" ]]; then
    return 0
  fi

  local proxy_port_file="\${WSL_PROXY_PORT_FILE:-\$HOME/.wsl-proxy.port}"
  local proxy_host="\${WIN_PROXY_HOST:-127.0.0.1}"
  local proxy_port="\${WIN_PROXY_PORT:-}"
  if [[ -z "\$proxy_port" && -f "\$proxy_port_file" ]]; then
    proxy_port="\$(awk 'NF {print \$1; exit}' "\$proxy_port_file" 2>/dev/null || true)"
  fi
  proxy_port="\${proxy_port:-\${WSL_PROXY_DEFAULT_PORT:-4062}}"

  export WIN_PROXY_HOST="\$proxy_host"
  export WIN_PROXY_PORT="\$proxy_port"
  export http_proxy="http://\$WIN_PROXY_HOST:\$WIN_PROXY_PORT"
  export https_proxy="\$http_proxy"
  export HTTP_PROXY="\$http_proxy"
  export HTTPS_PROXY="\$http_proxy"
  unset ALL_PROXY
  unset all_proxy

  local default_no_proxy="localhost,127.0.0.1,::1,.local,*.local,host.docker.internal,gateway.docker.internal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16"
  export NO_PROXY="\${NO_PROXY:-\$default_no_proxy}"
  export no_proxy="\${no_proxy:-\$NO_PROXY}"
}

load_wsl_proxy_env
preflight_codex_app_server
PROMPT_TEXT="\$(cat "\$PROMPT_FILE")"
exec "\$CODEX_BIN" --dangerously-bypass-approvals-and-sandbox -C "\$WORKTREE" -m "\$MODEL" -c "model_reasoning_effort=\"\$REASONING_EFFORT\"" "\$PROMPT_TEXT"
EOF_RUNNER
}

print_observation_info() {
  local launch_mode="interactive-visible"
  if [[ "$EXEC_MODE" -eq 1 ]]; then
    launch_mode="headless-exec"
  fi

  log ""
  log "=== Codex Worker Terminal ==="
  log ""
  log "Worktree: $WORKTREE"
  log "Tmux session: $TMUX_SESSION"
  log "Prompt file: $PROMPT_FILE"
  log "Terminal title: $WORKER_TITLE"
  log "Mode: $launch_mode"
  log "Model: $MODEL"
  log "Reasoning effort: $REASONING_EFFORT"
  log ""
  log "观察命令:"
  log "  cd $(printf '%q' "$WORKTREE")"
  log "  tmux attach -t $(printf '%q' "$TMUX_SESSION")"
  log ""
  log "进程确认:"
  log "  tmux list-panes -a -F '#{session_name} #{pane_current_path} #{pane_current_command}' | rg $(printf '%q' "$TMUX_SESSION|$WORKTREE")"
  log ""
  log "文件变化观察:"
  log "  watch -n 1 'git -C $(printf '%q' "$WORKTREE") status --short && echo && git -C $(printf '%q' "$WORKTREE") diff --stat'"
  log ""
  if [[ "$EXEC_MODE" -eq 1 ]]; then
    log "[WARN] --exec is headless one-shot mode; it does not leave a live Codex CLI agent pane after completion."
    log ""
  fi
}

verify_interactive_tmux_launch() {
  if [[ "$EXEC_MODE" -eq 1 ]]; then
    return 0
  fi

  local current_command=""
  local current_path=""
  local pane_text=""
  for _ in {1..80}; do
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      current_command="$(tmux display-message -p -t "$TMUX_SESSION:0.0" '#{pane_current_command}' 2>/dev/null || true)"
      current_path="$(tmux display-message -p -t "$TMUX_SESSION:0.0" '#{pane_current_path}' 2>/dev/null || true)"
      pane_text="$(tmux capture-pane -pt "$TMUX_SESSION:0.0" -S -80 2>/dev/null || true)"
      if [[ "$current_command" == "codex" && "$pane_text" == *"OpenAI Codex"* ]]; then
        log "Verified live Codex pane: session=$TMUX_SESSION command=$current_command path=$current_path"
        return 0
      fi
    fi
    sleep 0.25
  done

  log "[WARN] Codex worker did not verify as a live interactive pane."
  log "[WARN] Last observed: session=$TMUX_SESSION command=${current_command:-missing} path=${current_path:-missing}"
  log "[WARN] Expected pane_current_command=codex. Treat this worker as not running until inspected."
  return 1
}

render_launcher_script() {
  cat <<EOF_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail

WORKTREE='$WORKTREE'
TMUX_SESSION='$TMUX_SESSION'
PROMPT_FILE='$PROMPT_FILE'
RUNNER_PATH='$RUNNER_PATH'
WORKER_TITLE='$WORKER_TITLE'
REASONING_EFFORT='$REASONING_EFFORT'
MODEL='$MODEL'
EXEC_MODE='$EXEC_MODE'
CODEX_BIN='$CODEX_BIN'
APP_SERVER_PREFLIGHT='$APP_SERVER_PREFLIGHT'

cd "$WORKTREE"
printf '\\033]0;%s\\007' "$WORKER_TITLE"
printf '=== Codex Worker: %s ===\\n' "$WORKER_TITLE"
printf 'Worktree: %s\\n' "$WORKTREE"
printf 'Tmux: tmux attach -t %s\\n' "$TMUX_SESSION"
printf 'Prompt: %s\\n' "$PROMPT_FILE"
printf -- '---\\n'
if [[ "$EXEC_MODE" -eq 1 ]]; then
  printf 'Command: cat %q | %s exec --dangerously-bypass-approvals-and-sandbox -C %q -m %q -c %q --skip-git-repo-check --color never -\\n' \
    "$PROMPT_FILE" "$CODEX_BIN" "$WORKTREE" "$MODEL" "model_reasoning_effort=\"$REASONING_EFFORT\""
else
  printf 'Command: %s --dangerously-bypass-approvals-and-sandbox -C %q -m %q -c %q [prompt from %q]\\n' \
    "$CODEX_BIN" "$WORKTREE" "$MODEL" "model_reasoning_effort=\"$REASONING_EFFORT\"" "$PROMPT_FILE"
fi

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  if [[ "$EXEC_MODE" -eq 1 ]]; then
    tmux new-session -d -s "$TMUX_SESSION" "bash"
    sleep 0.2
    tmux send-keys -t "$TMUX_SESSION:0.0" "cd '$WORKTREE'" Enter
    tmux send-keys -t "$TMUX_SESSION:0.0" "cat '$PROMPT_FILE' | '$CODEX_BIN' exec --dangerously-bypass-approvals-and-sandbox -C '$WORKTREE' -m '$MODEL' -c 'model_reasoning_effort=\"$REASONING_EFFORT\"' --skip-git-repo-check --color never -" Enter
  else
    tmux new-session -d -s "$TMUX_SESSION" "$RUNNER_PATH"
    codex_ready=0
    for _ in {1..120}; do
      current_command="\$(tmux display-message -p -t "$TMUX_SESSION:0.0" '#{pane_current_command}' 2>/dev/null || true)"
      pane_text="\$(tmux capture-pane -pt "$TMUX_SESSION:0.0" -S -80 2>/dev/null || true)"
      if [[ "\$current_command" == "codex" && "\$pane_text" == *"OpenAI Codex"* ]]; then
        codex_ready=1
        break
      fi
      sleep 0.25
    done
    if [[ "\$codex_ready" -ne 1 ]]; then
      printf '[ERROR] Codex CLI did not become active; prompt delivery could not be verified.\\n' >&2
      printf '[ERROR] Inspect with: tmux attach -t %s\\n' "$TMUX_SESSION" >&2
    fi
  fi
else
  current_command="\$(tmux display-message -p -t "$TMUX_SESSION:0.0" '#{pane_current_command}' 2>/dev/null || true)"
  if [[ "$EXEC_MODE" -eq 0 && "\$current_command" != "codex" ]]; then
    printf '[WARN] Existing tmux session is not showing a live Codex pane: %s\\n' "\${current_command:-missing}" >&2
  fi
fi

tmux attach -t "$TMUX_SESSION"
EOF_LAUNCHER
}

write_launcher_script() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN write %q with content:\n' "$RUNNER_PATH"
    render_codex_runner_script
    printf 'DRY-RUN write %q with content:\n' "$LAUNCHER_PATH"
    render_launcher_script
    return 0
  fi

  mkdir -p "$LAUNCHER_DIR"
  render_codex_runner_script > "$RUNNER_PATH"
  chmod +x "$RUNNER_PATH"
  render_launcher_script > "$LAUNCHER_PATH"
  chmod +x "$LAUNCHER_PATH"
}

find_existing_cx_worker_session() {
  local session
  while IFS= read -r session; do
    case "$session" in
      "codex-${CX_WORKER_NAME}-"*)
        printf '%s\n' "$session"
        return 0
        ;;
    esac
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  return 1
}

if [[ "$TG_GATEWAY_CX_GUARD" -eq 1 ]]; then
  log "CX worker duplicate guard: worker=$CX_WORKER_NAME session-pattern=$CX_WORKER_SESSION_PATTERN"
  if existing_session="$(find_existing_cx_worker_session)"; then
    log "SKIP $CX_WORKER_NAME: existing Codex tmux session $existing_session"
    exit 0
  fi
fi

write_launcher_script
print_observation_info

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$EXEC_MODE" -eq 1 ]]; then
    printf '%s\n' "DRY-RUN launch command: cat '$PROMPT_FILE' | $CODEX_CMD_LINE"
  else
    printf '%s\n' "DRY-RUN launch command: $CODEX_CMD_LINE"
    printf '%s\n' "DRY-RUN prompt action: pass '$PROMPT_FILE' content as the initial interactive Codex prompt"
  fi
  if [[ "$TERMINAL_MODE" == "window" ]]; then
    log "DRY-RUN cmd: $WT_PATH new-window --title $(printf '%q' "$WORKER_TITLE") wsl.exe -- bash $(printf '%q' "$LAUNCHER_PATH")"
  else
    log "DRY-RUN cmd: $WT_PATH --window 0 new-tab --title $(printf '%q' "$WORKER_TITLE") wsl.exe -- bash $(printf '%q' "$LAUNCHER_PATH")"
  fi
  exit 0
fi

if [[ ! -f "$WT_PATH" ]]; then
  log "[WARN] Windows Terminal not found: $WT_PATH"
  log "[WARN] Visible CX terminal was not launched."
  log "Manual fallback command: bash $(printf '%q' "$LAUNCHER_PATH")"
  exit 0
fi

WT_ARGS=("--window" "0" "new-tab" "--title" "$WORKER_TITLE")
if [[ "$TERMINAL_MODE" == "window" ]]; then
  WT_ARGS=("new-window" "--title" "$WORKER_TITLE")
fi

"$WT_PATH" "${WT_ARGS[@]}" "wsl.exe" "--" "bash" "$LAUNCHER_PATH"

verify_interactive_tmux_launch
