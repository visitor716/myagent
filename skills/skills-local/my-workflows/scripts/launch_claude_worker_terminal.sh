#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
WT_PATH="/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe"

WORKTREE=""
TASK_SLUG=""
PROMPT_FILE=""
TERMINAL_MODE="tab"
TERMINAL_TITLE=""
COMPACT_AFTER_TASK=0
COMPACT_WAIT_SECONDS=5
DRY_RUN=0
VERBOSE=0

usage() {
  cat <<'EOF'
Usage:
  launch_claude_worker_terminal.sh --worktree <path> --task-slug <slug> --prompt-file <path> [options]

Options:
  --worktree <path>       Required. Path to Claude worker worktree.
  --task-slug <slug>      Required. Short task identifier for tmux session name.
  --prompt-file <path>    Required. Path to handoff prompt file.
  --terminal-mode <mode>  Optional. tab|window. Default: tab.
  --title <title>         Optional. Windows Terminal tab title. Default: worktree basename.
  --compact               Optional. Send /compact after task completion marker. Default: disabled.
  --no-compact            Optional. Compatibility no-op; post-task compact is disabled by default.
  --compact-wait <sec>    Optional. Seconds to wait before post-task /compact when --compact is set. Default: 5.
  --dry-run               Print commands without executing.
  --verbose               Print verbose output.
  -h, --help              Show this help.
EOF
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

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

wsl_to_windows_path() {
  local wsl_path="$1"
  if command -v wslpath &> /dev/null; then
    wslpath -w "$wsl_path" 2>/dev/null || echo "$wsl_path"
  else
    echo "$wsl_path"
  fi
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
    --terminal-mode)
      [[ $# -ge 2 ]] || die "--terminal-mode requires a value"
      TERMINAL_MODE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || die "--title requires a value"
      TERMINAL_TITLE="$2"
      shift 2
      ;;
    --compact)
      COMPACT_AFTER_TASK=1
      shift
      ;;
    --no-compact)
      COMPACT_AFTER_TASK=0
      shift
      ;;
    --compact-wait)
      [[ $# -ge 2 ]] || die "--compact-wait requires a value"
      COMPACT_WAIT_SECONDS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
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
[[ -f "$PROMPT_FILE" ]] || die "Prompt file not found: $PROMPT_FILE"
[[ -d "$WORKTREE" ]] || die "Worktree not found: $WORKTREE"
case "$TERMINAL_MODE" in
  tab|window) ;;
  *) die "--terminal-mode must be tab or window" ;;
esac
case "$COMPACT_WAIT_SECONDS" in
  ''|*[!0-9]*) die "--compact-wait must be a non-negative integer" ;;
esac
if [[ -z "$TERMINAL_TITLE" ]]; then
  TERMINAL_TITLE="$(basename "$WORKTREE")"
fi

TMUX_SESSION="claude-${TASK_SLUG}"
CC_WORKER_NAME=""
if [[ "$TERMINAL_TITLE" =~ ^cc[0-9]+$ ]]; then
  CC_WORKER_NAME="$TERMINAL_TITLE"
elif [[ "$(basename "$WORKTREE")" =~ ^cc[0-9]+$ ]]; then
  CC_WORKER_NAME="$(basename "$WORKTREE")"
fi
TG_GATEWAY_CC_GUARD=0
if [[ -n "$CC_WORKER_NAME" ]]; then
  case "$WORKTREE" in
    "/home/zhanxp/worktrees/tg-agent-gateway/$CC_WORKER_NAME"|"/home/zhanxp/worktrees/tg-agent-gateway/$CC_WORKER_NAME/")
      TG_GATEWAY_CC_GUARD=1
      ;;
  esac
fi
CC_WORKER_SESSION_PATTERN=""
if [[ "$TG_GATEWAY_CC_GUARD" -eq 1 ]]; then
  CC_WORKER_SESSION_PATTERN="claude-${CC_WORKER_NAME}-*"
fi
LAUNCHER_DIR="$(dirname "$PROMPT_FILE")/../claude-launchers"
LAUNCHER_PATH="$LAUNCHER_DIR/${TASK_SLUG}.sh"
CLAUDE_PROMPT_PATH="$LAUNCHER_DIR/${TASK_SLUG}.prompt.md"
COMPLETION_MARKER="CLAUDE_TASK_DONE_${TASK_SLUG}"
if [[ "$COMPACT_AFTER_TASK" -ne 1 ]]; then
  COMPLETION_MARKER=""
fi

find_existing_cc_worker_session() {
  local session
  while IFS= read -r session; do
    case "$session" in
      "claude-${CC_WORKER_NAME}-"*)
        printf '%s\n' "$session"
        return 0
        ;;
    esac
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  return 1
}

render_claude_prompt() {
  cat "$PROMPT_FILE"
  if [[ "$COMPACT_AFTER_TASK" -ne 1 ]]; then
    return 0
  fi

  cat <<EOF

任务完成后，请在最终报告最后单独输出这一行，方便启动器自动清理 Claude Code 上下文：
$COMPLETION_MARKER
EOF
}

write_claude_prompt() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN write %q with content:\n' "$CLAUDE_PROMPT_PATH"
    render_claude_prompt
    return 0
  fi

  mkdir -p "$LAUNCHER_DIR"
  render_claude_prompt > "$CLAUDE_PROMPT_PATH"
}

render_launcher_script() {
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKTREE=$(printf '%q' "$WORKTREE")
CLAUDE_PROMPT_PATH=$(printf '%q' "$CLAUDE_PROMPT_PATH")
TMUX_SESSION=$(printf '%q' "$TMUX_SESSION")
TERMINAL_TITLE=$(printf '%q' "$TERMINAL_TITLE")
COMPACT_AFTER_TASK=$COMPACT_AFTER_TASK
COMPACT_WAIT_SECONDS=$COMPACT_WAIT_SECONDS
COMPLETION_MARKER=$(printf '%q' "$COMPLETION_MARKER")

cd "\$WORKTREE"

printf '\033]0;%s\007' "\$TERMINAL_TITLE"
echo '=== Claude Worker: $TASK_SLUG ==='
echo "Worktree: \$WORKTREE"
echo "Tmux: tmux attach -t \$TMUX_SESSION"
echo "Prompt: \$CLAUDE_PROMPT_PATH"
echo '---'
echo ''
EOF

  if [[ "$COMPACT_AFTER_TASK" -eq 1 ]]; then
    cat <<'EOF'
watch_for_completion_and_compact() {
  (
    for _ in {1..7200}; do
      if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        exit 0
      fi

      if tmux capture-pane -pt "$TMUX_SESSION:0.0" -S -200 2>/dev/null | grep -Fq "$COMPLETION_MARKER"; then
        sleep "$COMPACT_WAIT_SECONDS"
        tmux send-keys -t "$TMUX_SESSION:0.0" '/compact' Enter
        exit 0
      fi

      sleep 2
    done
  ) >/dev/null 2>&1 &
}
EOF
  fi

  cat <<EOF
if ! tmux has-session -t "\$TMUX_SESSION" 2>/dev/null; then
  tmux new-session -d -s "\$TMUX_SESSION" "bash -lc 'if [ -f .env ]; then source .env 2>/dev/null || true; fi; echo Starting Claude...; exec claude --permission-mode auto'"

  for _ in {1..40}; do
    if tmux capture-pane -pt "\$TMUX_SESSION:0.0" -S -40 2>/dev/null | grep -q 'Claude Code'; then
      break
    fi
    sleep 0.25
  done

  if [[ "\$COMPACT_AFTER_TASK" -eq 1 ]]; then
    watch_for_completion_and_compact
  fi

  tmux load-buffer -b "\$TMUX_SESSION-prompt" "\$CLAUDE_PROMPT_PATH"
  tmux paste-buffer -b "\$TMUX_SESSION-prompt" -t "\$TMUX_SESSION:0.0"
  tmux send-keys -t "\$TMUX_SESSION:0.0" Enter
  tmux delete-buffer -b "\$TMUX_SESSION-prompt" 2>/dev/null || true
fi

tmux attach -t "\$TMUX_SESSION"
EOF
}

write_launcher_script() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    write_claude_prompt
    printf 'DRY-RUN write %q with content:\n' "$LAUNCHER_PATH"
    render_launcher_script
    return 0
  fi

  mkdir -p "$LAUNCHER_DIR"
  write_claude_prompt
  render_launcher_script > "$LAUNCHER_PATH"
  chmod +x "$LAUNCHER_PATH"
}

vlog "Worktree: $WORKTREE"
vlog "Task slug: $TASK_SLUG"
vlog "Prompt file: $PROMPT_FILE"
vlog "Tmux session: $TMUX_SESSION"
vlog "Terminal mode: $TERMINAL_MODE"
vlog "Terminal title: $TERMINAL_TITLE"
vlog "Compact after task: $COMPACT_AFTER_TASK"
vlog "Compact wait seconds: $COMPACT_WAIT_SECONDS"
vlog "Completion marker: $COMPLETION_MARKER"
vlog "CC worker name: $CC_WORKER_NAME"
vlog "TG gateway cc guard: $TG_GATEWAY_CC_GUARD"
vlog "CC worker session pattern: $CC_WORKER_SESSION_PATTERN"
vlog "Launcher path: $LAUNCHER_PATH"
vlog "Claude prompt path: $CLAUDE_PROMPT_PATH"

if [[ "$TG_GATEWAY_CC_GUARD" -eq 1 ]]; then
  log "CC worker duplicate guard: worker=$CC_WORKER_NAME session-pattern=$CC_WORKER_SESSION_PATTERN"
  if existing_session="$(find_existing_cc_worker_session)"; then
    log "SKIP $CC_WORKER_NAME: existing Claude tmux session $existing_session"
    exit 0
  fi
fi

# Print observation commands
log ""
log "=== Claude Worker Terminal ==="
log ""
log "Worktree: $WORKTREE"
log "Tmux session: $TMUX_SESSION"
log "Prompt file: $PROMPT_FILE"
log "Terminal title: $TERMINAL_TITLE"
log "Compact after task: $([[ "$COMPACT_AFTER_TASK" -eq 1 ]] && printf yes || printf no)"
if [[ "$COMPACT_AFTER_TASK" -eq 1 ]]; then
  log "Compact wait seconds: $COMPACT_WAIT_SECONDS"
  log "Completion marker: $COMPLETION_MARKER"
else
  log "Compact wait seconds: n/a"
  log "Completion marker: disabled"
fi
log ""
log "观察命令:"
log "  cd $(printf '%q' "$WORKTREE")"
log "  tmux attach -t $(printf '%q' "$TMUX_SESSION")"
log ""
log "文件变化观察:"
log "  watch -n 1 'git -C $(printf '%q' "$WORKTREE") status --short && echo && git -C $(printf '%q' "$WORKTREE") diff --stat'"
log ""

# Check if wt.exe exists
if [[ ! -f "$WT_PATH" ]]; then
  log "[WARN] Windows Terminal not found at: $WT_PATH"
  log "[WARN] Falling back to manual execution mode"
  write_claude_prompt
  log ""
  log "手动运行命令:"
  log "  cd $(printf '%q' "$WORKTREE")"
  log "  tmux new-session -d -s $(printf '%q' "$TMUX_SESSION") \"bash -lc 'if [ -f .env ]; then source .env 2>/dev/null || true; fi; exec claude --permission-mode auto'\""
  if [[ "$COMPACT_AFTER_TASK" -eq 1 ]]; then
    log "  # 如果需要手动保持 compact 行为，监听 $COMPLETION_MARKER 后发送 /compact"
  else
    log "  # 本次不会自动发送 /compact"
  fi
  log "  tmux load-buffer -b $(printf '%q' "$TMUX_SESSION")-prompt $(printf '%q' "$CLAUDE_PROMPT_PATH")"
  log "  tmux paste-buffer -b $(printf '%q' "$TMUX_SESSION")-prompt -t $(printf '%q' "$TMUX_SESSION"):0.0"
  log "  tmux send-keys -t $(printf '%q' "$TMUX_SESSION"):0.0 Enter"
  log "  tmux attach -t $(printf '%q' "$TMUX_SESSION")"
  exit 0
fi

# Build wt.exe arguments. Windows Terminal uses subcommands such as
# `new-tab`; `--tab` is not a valid wt.exe option and opens an error dialog.
WT_ARGS=()

if [[ "$TERMINAL_MODE" == "window" ]]; then
  WT_ARGS+=("new-tab" "--title" "$TERMINAL_TITLE")
else
  WT_ARGS+=("--window" "0")
  WT_ARGS+=("new-tab" "--title" "$TERMINAL_TITLE")
fi

write_launcher_script

# Keep the wt.exe command simple. Windows Terminal treats semicolons as command
# separators, so do not pass a nested shell program through `bash -c` here.
FINAL_CMD=("wsl.exe" "--" "bash" "$LAUNCHER_PATH")

vlog "Windows Terminal path: $WT_PATH"
vlog "Launcher command: ${FINAL_CMD[*]}"

log "Launching Windows Terminal..."

# Execute wt.exe
run "$WT_PATH" "${WT_ARGS[@]}" "${FINAL_CMD[@]}"

log "Done."
