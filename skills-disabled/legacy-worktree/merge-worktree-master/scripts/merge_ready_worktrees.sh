#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="/home/zhanxp/projects/tg-agent-gateway"
DEFAULT_WORKERS="cc2 cc3 cc4 cc5 cc6 cc7 cc8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/worktree_activity.sh"

REPO="$DEFAULT_REPO"
BASE_REF="master"
WORKERS="$DEFAULT_WORKERS"
APPLY=false
FETCH=true
INCLUDE_ACTIVE=false
VERIFY_CMD="npm run verify"
KEEP_INTEGRATION=false
INTEGRATION_BRANCH=""
RELEASE_NOTIFY=true
ACTIVITY_SETTLE_SECONDS="${TG_WORKTREE_ACTIVITY_SETTLE_SECONDS:-3}"

READY_WORKERS=()
READY_BRANCHES=()
SKIPPED_LINES=()

usage() {
  cat <<'EOF'
Usage: merge_ready_worktrees.sh [options]

Safely batch-merge ready tg-agent-gateway worker worktrees.
Default mode is --dry-run. No branch is modified unless --apply is set.

Options:
  --dry-run                 Preview only (default)
  --apply                   Merge ready branches through a temporary integration worktree
  --repo <path>             Main repo path (default: /home/zhanxp/projects/tg-agent-gateway)
  --base <ref>              Base branch/ref (default: master)
  --workers "<list>"        Space-separated workers (default: cc2 cc3 cc4 cc5 cc6 cc7 cc8)
  --include-active          Do not skip worktrees with busy or unknown local activity
  --activity-settle-seconds <n>
                            Seconds to sample tmux output before treating a pane as idle (default: 3)
  --verify <command>        Verification command for apply mode (default: npm run verify)
  --no-verify               Skip verification in apply mode
  --integration-branch <b>  Use a specific integration branch name
  --keep-integration        Keep temporary integration worktree/branch after success
  --no-release-notify       Do not restart Gateway or send the App notification after apply
  --no-fetch                Skip git fetch origin --prune
  -h, --help                Show this help

Safety:
  - Dirty, busy, unchanged, behind, diverged, missing, or invalid worktrees are skipped.
  - Clean worktrees with only quiet tmux panes are allowed; they are occupied,
    not busy.
  - Apply mode leaves master unchanged if merge or verification fails.
  - After a verified master fast-forward, apply mode restarts Gateway and sends
    the latest /app release notification by default.
  - The script never runs git reset --hard, git clean, force push, or push.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      APPLY=false
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
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
    --include-active)
      INCLUDE_ACTIVE=true
      shift
      ;;
    --activity-settle-seconds)
      [[ $# -ge 2 ]] || { echo "Missing value for --activity-settle-seconds" >&2; exit 2; }
      ACTIVITY_SETTLE_SECONDS="$2"
      shift 2
      ;;
    --verify)
      [[ $# -ge 2 ]] || { echo "Missing value for --verify" >&2; exit 2; }
      VERIFY_CMD="$2"
      shift 2
      ;;
    --no-verify)
      VERIFY_CMD=""
      shift
      ;;
    --integration-branch)
      [[ $# -ge 2 ]] || { echo "Missing value for --integration-branch" >&2; exit 2; }
      INTEGRATION_BRANCH="$2"
      shift 2
      ;;
    --keep-integration)
      KEEP_INTEGRATION=true
      shift
      ;;
    --no-release-notify)
      RELEASE_NOTIFY=false
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

run_git() {
  git -C "$REPO" "$@"
}

short_head() {
  git -C "$1" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

worker_path() {
  local worker="$1"
  local repo_name
  repo_name="$(basename "$REPO")"
  printf '%s\n' "$(cd "$REPO/../.." && pwd)/worktrees/$repo_name/$worker"
}

add_skip() {
  SKIPPED_LINES+=("$1: $2")
}

require_repo() {
  [[ -d "$REPO" ]] || die "Repo not found: $REPO"
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git worktree: $REPO"
  git -C "$REPO" rev-parse --verify --quiet "$BASE_REF" >/dev/null || die "Base ref not found: $BASE_REF"
}

scan_worker() {
  local worker="$1"
  local path branch status occupied panes busy idle counts behind ahead

  path="$(worker_path "$worker")"
  if [[ ! -d "$path" ]]; then
    add_skip "$worker" "missing worktree ($path)"
    return
  fi
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    add_skip "$worker" "path is not a git worktree ($path)"
    return
  fi

  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    add_skip "$worker" "detached HEAD"
    return
  fi

  status="$(git -C "$path" status --short)"
  if [[ -n "$status" ]]; then
    local dirty_count
    dirty_count="$(printf '%s\n' "$status" | sed '/^$/d' | wc -l | tr -d ' ')"
    add_skip "$worker" "dirty worktree ($dirty_count file(s)) branch=$branch"
    return
  fi

  read -r occupied panes busy idle <<<"$(worktree_activity_summary "$path" "$ACTIVITY_SETTLE_SECONDS")"
  if [[ "$busy" != "0" && "$INCLUDE_ACTIVE" != "true" ]]; then
    add_skip "$worker" "busy/unknown activity count $busy occupied=$occupied panes=$panes branch=$branch"
    return
  fi

  if ! counts="$(git -C "$path" rev-list --left-right --count "$BASE_REF...HEAD" 2>/dev/null)"; then
    add_skip "$worker" "cannot compare $BASE_REF...HEAD branch=$branch"
    return
  fi
  read -r behind ahead <<<"$counts"

  if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
    add_skip "$worker" "no changes ahead of $BASE_REF branch=$branch"
    return
  fi
  if [[ "$ahead" == "0" && "$behind" != "0" ]]; then
    add_skip "$worker" "behind $BASE_REF by $behind commit(s), no worker commits branch=$branch"
    return
  fi
  if [[ "$behind" != "0" ]]; then
    add_skip "$worker" "diverged from $BASE_REF (behind=$behind ahead=$ahead) branch=$branch"
    return
  fi

  READY_WORKERS+=("$worker")
  READY_BRANCHES+=("$branch")
  echo "READY $worker: branch=$branch ahead=$ahead head=$(short_head "$path") occupied=$occupied busy=$busy idle_panes=$idle"
}

print_summary() {
  echo
  echo "== Summary =="
  echo "repo: $REPO"
  echo "base: $BASE_REF"
  echo "mode: $($APPLY && echo apply || echo dry-run)"
  echo "ready: ${#READY_WORKERS[@]}"
  echo "skipped: ${#SKIPPED_LINES[@]}"

  if [[ ${#SKIPPED_LINES[@]} -gt 0 ]]; then
    echo
    echo "== Skipped =="
    printf '%s\n' "${SKIPPED_LINES[@]}"
  fi
}

assert_main_ready_for_apply() {
  local current status
  current="$(run_git branch --show-current)"
  [[ "$current" == "$BASE_REF" ]] || die "Main repo must be on $BASE_REF, current=$current"

  status="$(run_git status --short)"
  [[ -z "$status" ]] || {
    echo "Main repo is dirty; refusing apply:" >&2
    printf '%s\n' "$status" >&2
    exit 1
  }
}

publish_app_release() {
  local restart_script="$REPO/scripts/restart-gateway.sh"

  if [[ "$RELEASE_NOTIFY" != "true" ]]; then
    echo
    echo "APP RELEASE: skipped (--no-release-notify)"
    return
  fi

  if [[ "$BASE_REF" != "master" ]]; then
    echo
    echo "APP RELEASE: skipped (base is $BASE_REF, not master)"
    return
  fi

  [[ -f "$restart_script" ]] || die "Restart script not found: $restart_script"

  echo
  echo "APP RELEASE: restart Gateway and notify latest /app"
  (cd "$REPO" && bash scripts/restart-gateway.sh)

  echo
  echo "APP HEALTH: http://127.0.0.1:3000/health"
  curl -fsS http://127.0.0.1:3000/health >/dev/null
  echo "APP RELEASE: health ok"
}

apply_ready_merges() {
  local timestamp integration_branch tmp_worktree old_head new_head i branch worker

  [[ ${#READY_WORKERS[@]} -gt 0 ]] || {
    echo "No ready worktrees to merge."
    return
  }

  assert_main_ready_for_apply

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  integration_branch="${INTEGRATION_BRANCH:-integration/merge-worktree-master-$timestamp-$$}"
  tmp_worktree="${TMPDIR:-/tmp}/merge-worktree-master-$timestamp-$$"
  old_head="$(run_git rev-parse --short "$BASE_REF")"

  echo
  echo "== Apply =="
  echo "master head before: $old_head"
  echo "integration branch: $integration_branch"
  echo "integration worktree: $tmp_worktree"

  run_git worktree add -b "$integration_branch" "$tmp_worktree" "$BASE_REF"

  for i in "${!READY_WORKERS[@]}"; do
    worker="${READY_WORKERS[$i]}"
    branch="${READY_BRANCHES[$i]}"
    echo
    echo "MERGE $worker: $branch -> $integration_branch"
    if ! git -C "$tmp_worktree" merge --no-ff -m "Merge branch '$branch' from $worker" "$branch"; then
      echo "Merge failed for $worker. Attempting merge --abort in integration worktree." >&2
      git -C "$tmp_worktree" merge --abort >/dev/null 2>&1 || true
      echo "Integration worktree kept for inspection: $tmp_worktree" >&2
      exit 1
    fi
  done

  if [[ -n "$VERIFY_CMD" ]]; then
    echo
    echo "VERIFY: $VERIFY_CMD"
    if ! (cd "$tmp_worktree" && bash -lc "$VERIFY_CMD"); then
      echo "Verification failed. Master unchanged." >&2
      echo "Integration worktree kept for inspection: $tmp_worktree" >&2
      exit 1
    fi
  else
    echo
    echo "VERIFY: skipped (--no-verify)"
  fi

  echo
  echo "FAST-FORWARD $BASE_REF -> $integration_branch"
  run_git merge --ff-only "$integration_branch"
  new_head="$(run_git rev-parse --short "$BASE_REF")"
  echo "master head after: $new_head"

  if [[ "$KEEP_INTEGRATION" == "true" ]]; then
    echo "Integration kept: $tmp_worktree ($integration_branch)"
  else
    run_git worktree remove "$tmp_worktree"
    run_git branch -d "$integration_branch"
    echo "Integration cleaned up."
  fi

  publish_app_release
}

main() {
  REPO="$(cd "$REPO" && pwd)"
  require_repo

  if [[ "$FETCH" == "true" ]]; then
    git -C "$REPO" fetch origin --prune || echo "WARN: fetch failed; continuing with local refs" >&2
  fi

  echo "== Scan =="
  for worker in $WORKERS; do
    scan_worker "$worker"
  done

  print_summary

  if [[ "$APPLY" == "true" ]]; then
    apply_ready_merges
  else
    echo
    echo "Dry-run only. Re-run with --apply to merge ready worktrees."
  fi
}

main "$@"
