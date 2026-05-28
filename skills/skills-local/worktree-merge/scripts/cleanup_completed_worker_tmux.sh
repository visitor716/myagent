#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="/home/zhanxp/projects/tg-agent-gateway"
DEFAULT_WORKERS="cc2 cc3 cc4 cc5 cc6 cc7 cc8"

REPO="$DEFAULT_REPO"
BASE_REF="master"
WORKERS="$DEFAULT_WORKERS"
APPLY=false
FETCH=true

usage() {
  cat <<'EOF'
Usage: cleanup_completed_worker_tmux.sh [options]

Close completed Claude worker tmux sessions after their accepted work has been
merged/synced. Default mode is dry-run; no tmux session is killed unless
--apply is set.

Options:
  --repo <path>       Main repo path (default: /home/zhanxp/projects/tg-agent-gateway)
  --base <ref>        Accepted base ref (default: master)
  --workers "<list>"  Space-separated workers to inspect (default: cc2 cc3 cc4 cc5 cc6 cc7 cc8)
  --apply            Kill stale completed sessions
  --dry-run          Preview only (default)
  --no-fetch         Skip git fetch origin --prune
  -h, --help         Show this help

Safety:
  - Only considers tmux sessions named claude-* whose pane cwd is inside the
    worker worktree.
  - Skips dirty worktrees.
  - Skips workers whose branch is not contained in the accepted base ref.
  - Skips workers with active/planned DB rows.
  - Skips panes that do not look like a completed Claude final report.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --repo" >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || { echo "Missing value for --base" >&2; exit 2; }
      BASE_REF="$2"
      shift 2
      ;;
    --workers)
      [[ $# -ge 2 ]] || { echo "Missing value for --workers" >&2; exit 2; }
      WORKERS="$2"
      shift 2
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --dry-run)
      APPLY=false
      shift
      ;;
    --no-fetch)
      FETCH=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

die() {
  echo "ERROR: $*" >&2
  exit 1
}

worker_path() {
  local worker="$1"
  local repo_name
  repo_name="$(basename "$REPO")"
  printf '%s\n' "$(cd "$REPO/../.." && pwd)/worktrees/$repo_name/$worker"
}

db_active_count() {
  local worker="$1"
  local db query count

  command -v sqlite3 >/dev/null 2>&1 || { echo 0; return; }

  query="select count(*) from tasks where status in ('running','queued','planned','approved','pending','processing','cancel_requested') and (worker='$worker' or recommended_agent='$worker');"
  for db in "$REPO/data/gateway.sqlite" "$REPO/data/gateway.db"; do
    [[ -f "$db" ]] || continue
    count="$(sqlite3 "$db" "$query" 2>/dev/null || true)"
    if [[ "$count" =~ ^[0-9]+$ ]]; then
      echo "$count"
      return
    fi
  done

  echo 0
}

branch_contained_by_base() {
  local branch="$1"
  git -C "$REPO" merge-base --is-ancestor "$branch" "$BASE_REF" >/dev/null 2>&1
}

pane_looks_complete() {
  local target="$1"
  local text

  text="$(tmux capture-pane -pt "$target" -S -220 2>/dev/null || true)"
  [[ -n "$text" ]] || return 1

  if grep -Fq "CLAUDE_TASK_DONE" <<<"$text"; then
    return 0
  fi

  grep -Eiq 'Changed Files|### Changed Files' <<<"$text" \
    && grep -Eiq 'Verification|### Verification' <<<"$text" \
    && grep -Eiq 'Risks|### Risks' <<<"$text"
}

session_window_count() {
  local session="$1"
  tmux display-message -p -t "$session" '#{session_windows}' 2>/dev/null || echo 0
}

session_pane_count() {
  local session="$1"
  tmux list-panes -t "$session" 2>/dev/null | wc -l | tr -d ' '
}

scan_worker() {
  local worker="$1"
  local path branch status db_count found=0
  local session window pane cwd cmd title target windows panes

  path="$(worker_path "$worker")"
  if [[ ! -d "$path" ]]; then
    echo "SKIP $worker: missing worktree ($path)"
    return
  fi

  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "SKIP $worker: path is not a git worktree ($path)"
    return
  fi

  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    echo "SKIP $worker: detached HEAD"
    return
  fi

  while IFS='|' read -r session window pane cwd cmd title; do
    [[ -n "$session" ]] || continue
    [[ "$session" == claude-* ]] || continue
    [[ "$cwd" == "$path" || "$cwd" == "$path"/* ]] || continue

    found=1
    target="$session:$window.$pane"
    windows="$(session_window_count "$session")"
    panes="$(session_pane_count "$session")"

    status="$(git -C "$path" status --short)"
    if [[ -n "$status" ]]; then
      echo "KEEP $worker $session: dirty worktree"
      continue
    fi

    if ! branch_contained_by_base "$branch"; then
      echo "KEEP $worker $session: branch $branch is not contained in $BASE_REF"
      continue
    fi

    db_count="$(db_active_count "$worker")"
    if [[ "$db_count" != "0" ]]; then
      echo "KEEP $worker $session: active DB rows=$db_count"
      continue
    fi

    if [[ "$windows" != "1" ]]; then
      echo "KEEP $worker $session: session has $windows windows"
      continue
    fi

    if [[ "$panes" != "1" ]]; then
      echo "KEEP $worker $session: session has $panes panes"
      continue
    fi

    if ! pane_looks_complete "$target"; then
      echo "KEEP $worker $session: pane does not look complete"
      continue
    fi

    if [[ "$APPLY" == "true" ]]; then
      tmux kill-session -t "$session" 2>/dev/null || true
      echo "CLOSED $worker $session"
    else
      echo "STALE $worker $session: would close with --apply"
    fi
  done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{pane_current_command}|#{pane_title}' 2>/dev/null || true)

  if [[ "$found" == "0" ]]; then
    echo "OK $worker: no Claude tmux pane under worktree"
  fi
}

main() {
  REPO="$(cd "$REPO" && pwd)"
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git worktree: $REPO"
  git -C "$REPO" rev-parse --verify --quiet "$BASE_REF" >/dev/null || die "Base ref not found: $BASE_REF"

  if [[ "$FETCH" == "true" ]]; then
    git -C "$REPO" fetch origin --prune >/dev/null || echo "WARN: fetch failed; continuing with local refs" >&2
  fi

  echo "== Completed Worker Tmux Cleanup =="
  echo "repo: $REPO"
  echo "base: $BASE_REF"
  echo "mode: $($APPLY && echo apply || echo dry-run)"
  echo

  for worker in $WORKERS; do
    scan_worker "$worker"
  done
}

main "$@"
