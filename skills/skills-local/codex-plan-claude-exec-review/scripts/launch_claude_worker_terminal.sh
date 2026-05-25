#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
WT_PATH="/mnt/c/Users/zhanxp/AppData/Local/Microsoft/WindowsApps/wt.exe"

WORKTREE=""
TASK_SLUG=""
PROMPT_FILE=""
TERMINAL_MODE="tab"
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

TMUX_SESSION="claude-${TASK_SLUG}"

# Build the command that will run inside tmux
# Use a bash subshell to ensure the prompt is fed correctly
CLAUDE_CMD="cd $(printf '%q' "$WORKTREE") && tmux new-session -A -s $(printf '%q' "$TMUX_SESSION") 'bash -c \"[ -f .env ] && source .env; exec claude --permission-mode auto < $(printf '%q' "$PROMPT_FILE")\"'"

vlog "Worktree: $WORKTREE"
vlog "Task slug: $TASK_SLUG"
vlog "Prompt file: $PROMPT_FILE"
vlog "Tmux session: $TMUX_SESSION"
vlog "Terminal mode: $TERMINAL_MODE"

# Print observation commands
log ""
log "=== Claude Worker Terminal ==="
log ""
log "Worktree: $WORKTREE"
log "Tmux session: $TMUX_SESSION"
log "Prompt file: $PROMPT_FILE"
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
  log ""
  log "手动运行命令:"
  log "  cd $(printf '%q' "$WORKTREE")"
  log "  tmux new-session -A -s $(printf '%q' "$TMUX_SESSION") 'claude --permission-mode auto < $(printf '%q' "$PROMPT_FILE")'"
  exit 0
fi

# Build wt.exe arguments. Windows Terminal uses subcommands such as
# `new-tab`; `--tab` is not a valid wt.exe option and opens an error dialog.
WT_ARGS=()

if [[ "$TERMINAL_MODE" == "window" ]]; then
  WT_ARGS+=("new-tab")
else
  WT_ARGS+=("--window" "0")
  WT_ARGS+=("new-tab")
fi

# Build the WSL command line that wt.exe will execute
# Use bash -c to chain commands, and escape properly for Windows
WSL_CMD="cd $(printf '%q' "$WORKTREE") && "
WSL_CMD+="echo '=== Claude Worker: $TASK_SLUG ===' && "
WSL_CMD+="echo 'Worktree: $WORKTREE' && "
WSL_CMD+="echo 'Tmux: tmux attach -t $TMUX_SESSION' && "
WSL_CMD+="echo '---' && "
WSL_CMD+="echo '' && "
WSL_CMD+="tmux new-session -A -s $(printf '%q' "$TMUX_SESSION") 'bash -c \"[ -f .env ] && source .env 2>/dev/null; echo Starting Claude...; exec claude --permission-mode auto < $(printf '%q' "$PROMPT_FILE")\"'"

# Use wsl.exe to execute the command
# wt.exe expects Windows paths/arguments
FINAL_CMD=("wsl.exe" "bash" "-c" "$WSL_CMD")

vlog "Windows Terminal path: $WT_PATH"
vlog "WSL command: $WSL_CMD"

log "Launching Windows Terminal..."

# Execute wt.exe
run "$WT_PATH" "${WT_ARGS[@]}" "${FINAL_CMD[@]}"

log "Done."
