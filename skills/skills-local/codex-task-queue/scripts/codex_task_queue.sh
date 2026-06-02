#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_QUEUE_CWD="/home/zhanxp/worktrees/tg-agent-gateway/cx1"

COMMAND="${1:-}"
if [[ -n "$COMMAND" ]]; then
  shift
fi

CWD="$DEFAULT_QUEUE_CWD"
TITLE=""
SESSION=""
PANE="0.0"
MARKER="CODEX_TASK_DONE"
COMPACT_WAIT_SECONDS=5
AFTER_COMPACT_WAIT_SECONDS=8
POLL_INTERVAL_SECONDS=2
FORCE_NEXT=0

usage() {
  cat <<'EOF'
Usage:
  codexq add "requirement" [--cwd <path>] [--title <title>]
  codexq list [--cwd <path>]
  codexq status [--cwd <path>]
  codexq pause|resume [--cwd <path>]
  codexq next --session <tmux-session> [--pane 0.0] [--cwd <path>] [--force-next]
  codexq watch --session <tmux-session> [--pane 0.0] [--cwd <path>] [--marker CODEX_TASK_DONE]

Options:
  --cwd <path>                 Queue root repo. Default: /home/zhanxp/worktrees/tg-agent-gateway/cx1.
  --title <title>              Human title for add.
  --session <session>          Tmux session name or full target containing ':'.
  --pane <pane>                Tmux pane when --session is only a session name. Default: 0.0.
  --marker <marker>            Marker for the already-running current task. Default: CODEX_TASK_DONE.
  --compact-wait <seconds>     Seconds to wait after marker before /compact. Default: 5.
  --after-compact-wait <sec>   Seconds to wait after /compact before dispatch. Default: 8.
  --poll-interval <seconds>    Watch loop interval. Default: 2.
  --force-next                 Allow next to inject while running/ is non-empty.
  -h, --help                   Show help.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  ensure_dirs
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE"
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

sanitize_slug() {
  local raw="$1"
  local slug
  slug="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$slug" ]]; then
    slug="task"
  fi
  printf '%s' "${slug:0:48}"
}

resolve_queue_paths() {
  CWD="$(cd "$CWD" 2>/dev/null && pwd)" || die "cwd not found: $CWD"
  QUEUE_ROOT="$CWD/.omx/codex-task-queue"
  PENDING_DIR="$QUEUE_ROOT/pending"
  RUNNING_DIR="$QUEUE_ROOT/running"
  DONE_DIR="$QUEUE_ROOT/done"
  FAILED_DIR="$QUEUE_ROOT/failed"
  LOG_DIR="$QUEUE_ROOT/logs"
  STATE_DIR="$QUEUE_ROOT/state"
  LOG_FILE="$LOG_DIR/watcher.log"
  PAUSED_FILE="$STATE_DIR/paused"
}

ensure_dirs() {
  if [[ -z "${QUEUE_ROOT:-}" ]]; then
    resolve_queue_paths
  fi
  mkdir -p "$PENDING_DIR" "$RUNNING_DIR" "$DONE_DIR" "$FAILED_DIR" "$LOG_DIR" "$STATE_DIR"
}

parse_common_args() {
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd)
        [[ $# -ge 2 ]] || die "--cwd requires a value"
        CWD="$2"
        shift 2
        ;;
      --title)
        [[ $# -ge 2 ]] || die "--title requires a value"
        TITLE="$2"
        shift 2
        ;;
      --session)
        [[ $# -ge 2 ]] || die "--session requires a value"
        SESSION="$2"
        shift 2
        ;;
      --pane)
        [[ $# -ge 2 ]] || die "--pane requires a value"
        PANE="$2"
        shift 2
        ;;
      --marker)
        [[ $# -ge 2 ]] || die "--marker requires a value"
        MARKER="$2"
        shift 2
        ;;
      --compact-wait)
        [[ $# -ge 2 ]] || die "--compact-wait requires a value"
        COMPACT_WAIT_SECONDS="$2"
        is_uint "$COMPACT_WAIT_SECONDS" || die "--compact-wait must be a non-negative integer"
        shift 2
        ;;
      --after-compact-wait)
        [[ $# -ge 2 ]] || die "--after-compact-wait requires a value"
        AFTER_COMPACT_WAIT_SECONDS="$2"
        is_uint "$AFTER_COMPACT_WAIT_SECONDS" || die "--after-compact-wait must be a non-negative integer"
        shift 2
        ;;
      --poll-interval)
        [[ $# -ge 2 ]] || die "--poll-interval requires a value"
        POLL_INTERVAL_SECONDS="$2"
        is_uint "$POLL_INTERVAL_SECONDS" || die "--poll-interval must be a non-negative integer"
        shift 2
        ;;
      --force-next)
        FORCE_NEXT=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        POSITIONAL+=("$@")
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

target_pane() {
  [[ -n "$SESSION" ]] || die "--session is required"
  if [[ "$SESSION" == *:* ]]; then
    printf '%s' "$SESSION"
  else
    printf '%s:%s' "$SESSION" "$PANE"
  fi
}

require_tmux_target() {
  command -v tmux >/dev/null 2>&1 || die "tmux not found"
  local target="$1"
  tmux capture-pane -pt "$target" -S -1 >/dev/null 2>&1 || die "tmux target not available: $target"
}

metadata_value() {
  local file="$1"
  local key="$2"
  sed -n "s/^${key}: //p" "$file" | head -1
}

first_file() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*.md' | sort | head -1
}

file_count() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' '
}

marker_for_id() {
  local id="$1"
  printf 'CODEX_TASK_DONE_%s' "$(printf '%s' "$id" | tr '-' '_')"
}

read_add_body() {
  if [[ "${#POSITIONAL[@]}" -gt 0 ]]; then
    printf '%s\n' "${POSITIONAL[*]}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    cat
    return 0
  fi

  die "add requires requirement text or stdin"
}

command_add() {
  parse_common_args "$@"
  ensure_dirs

  local body
  body="$(read_add_body)"
  [[ -n "${body//[[:space:]]/}" ]] || die "requirement is empty"

  local title="$TITLE"
  if [[ -z "$title" ]]; then
    title="$(printf '%s' "$body" | sed -n '1p' | cut -c 1-80)"
  fi

  local ts slug id marker file
  ts="$(date +%Y%m%d-%H%M%S)"
  slug="$(sanitize_slug "$title")"
  id="${ts}-${slug}"
  marker="$(marker_for_id "$id")"
  file="$PENDING_DIR/${id}.md"

  if [[ -e "$file" ]]; then
    id="${id}-$$"
    marker="$(marker_for_id "$id")"
    file="$PENDING_DIR/${id}.md"
  fi

  cat > "$file" <<EOF
id: $id
title: $title
cwd: $CWD
created_at: $(date -Iseconds)
marker: $marker
---
$body
EOF

  log "added id=$id title=$title"
  printf 'Queued: %s\n' "$id"
  printf 'File: %s\n' "$file"
  printf 'Marker: %s\n' "$marker"
}

command_list() {
  parse_common_args "$@"
  ensure_dirs
  local count
  count="$(file_count "$PENDING_DIR")"
  printf 'Pending: %s\n' "$count"
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    printf '%s\n' "- $(metadata_value "$file" id) | $(metadata_value "$file" title) | $(metadata_value "$file" cwd)"
  done < <(find "$PENDING_DIR" -maxdepth 1 -type f -name '*.md' | sort)
}

command_status() {
  parse_common_args "$@"
  ensure_dirs
  printf 'Queue root: %s\n' "$QUEUE_ROOT"
  printf 'Pending: %s\n' "$(file_count "$PENDING_DIR")"
  printf 'Running: %s\n' "$(file_count "$RUNNING_DIR")"
  printf 'Done: %s\n' "$(file_count "$DONE_DIR")"
  printf 'Failed: %s\n' "$(file_count "$FAILED_DIR")"
  if [[ -f "$PAUSED_FILE" ]]; then
    printf 'Paused: yes\n'
  else
    printf 'Paused: no\n'
  fi
  local running
  running="$(first_file "$RUNNING_DIR" || true)"
  if [[ -n "$running" ]]; then
    printf 'Running task: %s | %s\n' "$(metadata_value "$running" id)" "$(metadata_value "$running" title)"
    printf 'Running marker: %s\n' "$(metadata_value "$running" marker)"
  fi
}

command_pause() {
  parse_common_args "$@"
  ensure_dirs
  date -Iseconds > "$PAUSED_FILE"
  log "paused"
  printf 'Paused queue: %s\n' "$QUEUE_ROOT"
}

command_resume() {
  parse_common_args "$@"
  ensure_dirs
  rm -f "$PAUSED_FILE"
  log "resumed"
  printf 'Resumed queue: %s\n' "$QUEUE_ROOT"
}

task_body() {
  local file="$1"
  sed '1,/^---$/d' "$file"
}

render_task_prompt() {
  local file="$1"
  local id title task_cwd quoted_cwd marker
  id="$(metadata_value "$file" id)"
  title="$(metadata_value "$file" title)"
  task_cwd="$(metadata_value "$file" cwd)"
  quoted_cwd="$(printf '%q' "$task_cwd")"
  marker="$(metadata_value "$file" marker)"

  cat <<EOF
你正在执行 Codex task queue 中的下一条任务。

任务 ID：$id
标题：$title

工作目录：
cd $quoted_cwd

执行要求：
- 先确认 pwd，并运行 git status --short。
- 遵循当前仓库 AGENTS.md 和用户已有偏好。
- 做最小必要修改；不要覆盖无关用户改动。
- 如果这是 tg-agent-gateway worktree 中的执行类任务，优先尊重 Codex 规划、Claude/cc worker 执行、Codex 审核的分工，除非任务明确要求 Codex 直接实现。
- 验证时优先运行与改动相关的命令；不要粘贴完整 diff、长日志或完整终端输出。
- 最终回复包含 Changed Files、Summary、Verification、Risks、Next Step。
- 最终回复最后单独输出这一行：
$marker

用户需求：
$(task_body "$file")
EOF
}

send_prompt_to_tmux() {
  local target="$1"
  local file="$2"
  local task_id
  task_id="$(metadata_value "$file" id)"
  local tmp
  tmp="$(mktemp)"
  render_task_prompt "$file" > "$tmp"
  tmux load-buffer -b "codexq-${task_id}" "$tmp"
  tmux paste-buffer -b "codexq-${task_id}" -t "$target"
  tmux send-keys -t "$target" Enter
  tmux delete-buffer -b "codexq-${task_id}" 2>/dev/null || true
  rm -f "$tmp"
}

dispatch_next() {
  local target="$1"
  ensure_dirs
  local running_count
  running_count="$(file_count "$RUNNING_DIR")"
  if [[ "$running_count" != "0" && "$FORCE_NEXT" -ne 1 ]]; then
    die "running task exists; use --force-next only for manual recovery"
  fi

  local next
  next="$(first_file "$PENDING_DIR" || true)"
  if [[ -z "$next" ]]; then
    log "no pending task to dispatch"
    printf 'No pending task.\n'
    return 2
  fi

  local dest
  dest="$RUNNING_DIR/$(basename "$next")"
  mv "$next" "$dest"

  if send_prompt_to_tmux "$target" "$dest"; then
    log "dispatched id=$(metadata_value "$dest" id) marker=$(metadata_value "$dest" marker) target=$target"
    printf 'Dispatched: %s\n' "$(metadata_value "$dest" id)"
    printf 'Marker: %s\n' "$(metadata_value "$dest" marker)"
  else
    mv "$dest" "$FAILED_DIR/$(basename "$dest")"
    log "failed dispatch file=$(basename "$dest")"
    die "failed to send prompt to tmux"
  fi
}

command_next() {
  parse_common_args "$@"
  ensure_dirs
  local target
  target="$(target_pane)"
  require_tmux_target "$target"
  dispatch_next "$target"
}

marker_count() {
  local target="$1"
  local marker="$2"
  tmux capture-pane -pt "$target" -S -3000 2>/dev/null |
    awk -v marker="$marker" 'index($0, marker) { count++ } END { print count + 0 }'
}

mark_running_done() {
  local running
  running="$(first_file "$RUNNING_DIR" || true)"
  if [[ -z "$running" ]]; then
    return 0
  fi
  local dest
  dest="$DONE_DIR/$(basename "$running")"
  mv "$running" "$dest"
  log "done id=$(metadata_value "$dest" id)"
}

current_running_marker() {
  local running
  running="$(first_file "$RUNNING_DIR" || true)"
  if [[ -n "$running" ]]; then
    metadata_value "$running" marker
    return 0
  fi
  printf '%s' "$MARKER"
}

command_watch() {
  parse_common_args "$@"
  ensure_dirs
  local target
  target="$(target_pane)"
  require_tmux_target "$target"

  local active_marker baseline count next_marker
  active_marker="$(current_running_marker)"
  baseline="$(marker_count "$target" "$active_marker")"
  log "watch start target=$target cwd=$CWD marker=$active_marker baseline=$baseline"
  printf 'Watching %s for marker %s (baseline=%s)\n' "$target" "$active_marker" "$baseline"
  printf 'Queue root: %s\n' "$QUEUE_ROOT"

  while true; do
    require_tmux_target "$target"

    next_marker="$(current_running_marker)"
    if [[ "$next_marker" != "$active_marker" ]]; then
      active_marker="$next_marker"
      baseline="$(marker_count "$target" "$active_marker")"
      log "marker switched marker=$active_marker baseline=$baseline"
      printf 'Now watching marker %s (baseline=%s)\n' "$active_marker" "$baseline"
    fi

    count="$(marker_count "$target" "$active_marker")"
    if (( count > baseline )); then
      log "marker detected marker=$active_marker count=$count baseline=$baseline"
      printf 'Detected marker %s\n' "$active_marker"
      sleep "$COMPACT_WAIT_SECONDS"
      tmux send-keys -t "$target" '/compact' Enter
      log "sent compact target=$target"
      sleep "$AFTER_COMPACT_WAIT_SECONDS"
      mark_running_done

      while [[ -f "$PAUSED_FILE" ]]; do
        log "paused after compact"
        sleep "$POLL_INTERVAL_SECONDS"
      done

      if dispatch_next "$target"; then
        active_marker="$(current_running_marker)"
        sleep 1
        baseline="$(marker_count "$target" "$active_marker")"
        log "watch next marker=$active_marker baseline=$baseline"
        printf 'Now watching marker %s (baseline=%s)\n' "$active_marker" "$baseline"
      else
        active_marker="$MARKER"
        baseline="$(marker_count "$target" "$active_marker")"
        log "idle marker=$active_marker baseline=$baseline"
        printf 'Queue empty. Waiting for marker %s (baseline=%s)\n' "$active_marker" "$baseline"
      fi
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done
}

case "$COMMAND" in
  add) command_add "$@" ;;
  list) command_list "$@" ;;
  status) command_status "$@" ;;
  pause) command_pause "$@" ;;
  resume) command_resume "$@" ;;
  next) command_next "$@" ;;
  watch) command_watch "$@" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $COMMAND"
    ;;
esac
