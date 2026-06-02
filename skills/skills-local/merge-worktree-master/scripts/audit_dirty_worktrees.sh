#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="/home/zhanxp/projects/tg-agent-gateway"
DEFAULT_BASE="master"
DEFAULT_WORKERS="cc1 cc2 cc3 cc4 cc5 cc6 cc7 cc8 cx1 cx2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/worktree_activity.sh"

REPO="$DEFAULT_REPO"
BASE_REF="$DEFAULT_BASE"
WORKERS="$DEFAULT_WORKERS"
EXPORT_DIR=""
FETCH=true
INCLUDE_ACTIVE=false
APPLY_ACCEPTED=false
DISCARD_WORKERS=""
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ACTIVITY_SETTLE_SECONDS="${TG_WORKTREE_ACTIVITY_SETTLE_SECONDS:-3}"

usage() {
  cat <<'EOF'
Usage: audit_dirty_worktrees.sh [options]

Audit dirty tg-agent-gateway worker worktrees before syncing worker refs.
Default mode is evidence-only: no worktree, branch, stash, or ref is modified.

Options:
  --repo <path>               Main repo path (default: /home/zhanxp/projects/tg-agent-gateway)
  --base <ref>                Base branch/ref (default: master)
  --workers "<list>"          Space-separated workers (default: cc1-cc8 cx1 cx2)
  --export-dir <path>         Evidence directory (default: .git/codex-backups/dirty-worktree-audit-<ts>)
  --apply-accepted            Backup, stash, and ff-only sync accepted-exact worktrees
  --stash-discarded "<list>"  Backup, stash, and ff-only sync reviewed discard workers
  --include-active            Allow action on worktrees with busy or unknown local activity
  --activity-settle-seconds <n>
                              Seconds to sample tmux output before treating a pane as idle (default: 3)
  --no-fetch                  Skip git fetch origin --prune
  -h, --help                  Show this help

Classification:
  accepted-exact  Dirty working tree state matches the base ref exactly and has no unique commits.
  keep-review     Dirty state differs from the base ref or has unique commits; preserve it for review.
  discard-candidate
                  Dirty mismatches are only patch/reject artifacts; stash only after review.

Safety:
  - The script never runs git reset --hard, git clean, force push, or push.
  - --apply-accepted only touches accepted-exact worktrees.
  - --stash-discarded requires an explicit worker list and refuses unique commits.
  - Busy worktrees are skipped unless --include-active is set.
  - Quiet tmux panes only count as occupied; they do not block accepted-exact
    or clean fast-forward handling.
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
    --export-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --export-dir" >&2; exit 2; }
      EXPORT_DIR="$2"
      shift 2
      ;;
    --apply-accepted)
      APPLY_ACCEPTED=true
      shift
      ;;
    --stash-discarded)
      [[ $# -ge 2 ]] || { echo "Missing value for --stash-discarded" >&2; exit 2; }
      DISCARD_WORKERS="$2"
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

sanitize() {
  printf '%s' "$1" | tr '/ ' '__'
}

worker_path() {
  local worker="$1"
  local repo_name
  repo_name="$(basename "$REPO")"
  printf '%s\n' "$(cd "$REPO/../.." && pwd)/worktrees/$repo_name/$worker"
}

contains_worker() {
  local needle="$1"
  local item

  for item in $DISCARD_WORKERS; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

dirty_paths() {
  local path="$1"

  {
    git -C "$path" diff --name-only
    git -C "$path" diff --cached --name-only
    git -C "$path" ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

base_has_path() {
  local rel="$1"
  git -C "$REPO" cat-file -e "$BASE_REF:$rel" 2>/dev/null
}

worktree_has_path() {
  local path="$1"
  local rel="$2"
  [[ -e "$path/$rel" || -L "$path/$rel" ]]
}

path_matches_base() {
  local path="$1"
  local rel="$2"
  local base_hash worktree_hash

  if base_has_path "$rel"; then
    worktree_has_path "$path" "$rel" || return 1
    [[ -f "$path/$rel" || -L "$path/$rel" ]] || return 1
    base_hash="$(git -C "$REPO" rev-parse "$BASE_REF:$rel")"
    worktree_hash="$(git -C "$path" hash-object -- "$rel")"
    [[ "$base_hash" == "$worktree_hash" ]]
    return
  fi

  ! worktree_has_path "$path" "$rel"
}

is_discard_artifact() {
  case "$1" in
    *.rej|*.orig|*.bak|*.patch)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

export_evidence() {
  local worker="$1"
  local path="$2"
  local safe_worker

  safe_worker="$(sanitize "$worker")"
  git -C "$path" status --short >"$EXPORT_DIR/${safe_worker}__status.txt"
  git -C "$path" diff --stat >"$EXPORT_DIR/${safe_worker}__diff_stat.txt" || true
  git -C "$path" diff --binary >"$EXPORT_DIR/${safe_worker}__unstaged.patch" || true
  git -C "$path" diff --cached --binary >"$EXPORT_DIR/${safe_worker}__staged.patch" || true
  git -C "$path" ls-files --others --exclude-standard >"$EXPORT_DIR/${safe_worker}__untracked.txt" || true
}

stash_and_fast_forward() {
  local worker="$1"
  local path="$2"
  local branch="$3"
  local behind="$4"
  local reason="$5"

  echo "ACTION $worker: backup+stash ($reason)"
  git -C "$path" stash push -u -m "dirty-audit $reason $worker $branch $TIMESTAMP"

  if [[ "$behind" != "0" ]]; then
    echo "ACTION $worker: ff-only $branch -> $BASE_REF by $behind commit(s)"
    git -C "$path" merge --ff-only "$BASE_REF"
  else
    echo "ACTION $worker: no fast-forward needed after stash"
  fi
}

scan_worker() {
  local worker="$1"
  local path branch head counts behind ahead status_output dirty_count occupied_count pane_count busy_count idle_count
  local safe_worker comparison_file rel class action match_count mismatch_count artifact_count

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
  [[ -n "$branch" ]] || { echo "SKIP $worker: detached HEAD"; return; }

  head="$(git -C "$path" rev-parse --short HEAD)"
  if ! counts="$(git -C "$REPO" rev-list --left-right --count "$BASE_REF...$branch" 2>/dev/null)"; then
    echo "SKIP $worker: cannot compare $BASE_REF...$branch"
    return
  fi
  read -r behind ahead <<<"$counts"

  status_output="$(git -C "$path" status --short)"
  dirty_count="$(printf '%s\n' "$status_output" | sed '/^$/d' | wc -l | tr -d ' ')"
  read -r occupied_count pane_count busy_count idle_count <<<"$(worktree_activity_summary "$path" "$ACTIVITY_SETTLE_SECONDS")"
  safe_worker="$(sanitize "$worker")"
  comparison_file="$EXPORT_DIR/${safe_worker}__path_comparison.txt"

  export_evidence "$worker" "$path"
  : >"$comparison_file"

  match_count=0
  mismatch_count=0
  artifact_count=0

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if path_matches_base "$path" "$rel"; then
      printf 'MATCH\t%s\n' "$rel" >>"$comparison_file"
      match_count=$((match_count + 1))
    else
      if is_discard_artifact "$rel"; then
        printf 'ARTIFACT\t%s\n' "$rel" >>"$comparison_file"
        artifact_count=$((artifact_count + 1))
      else
        printf 'DIFF\t%s\n' "$rel" >>"$comparison_file"
      fi
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(dirty_paths "$path")

  if [[ "$dirty_count" == "0" ]]; then
    class="clean"
    action="sync-with-standard-script-if-behind"
  elif [[ "$busy_count" != "0" && "$INCLUDE_ACTIVE" != "true" ]]; then
    class="busy-keep"
    action="keep"
  elif [[ "$ahead" != "0" ]]; then
    class="unique-worker-work"
    action="keep-review"
  elif [[ "$mismatch_count" == "0" ]]; then
    class="accepted-exact"
    action="can-apply-accepted"
  elif [[ "$mismatch_count" == "$artifact_count" ]]; then
    class="discard-candidate"
    action="stash-discarded-after-review"
  else
    class="keep-review"
    action="keep-or-stash-discarded-after-review"
  fi

  printf '%-4s branch=%-8s head=%-8s base_only=%-3s worker_only=%-3s dirty=%-3s occupied=%-3s panes=%-3s busy=%-3s idle_panes=%-3s match=%-3s mismatch=%-3s artifacts=%-3s class=%s action=%s\n' \
    "$worker" "$branch" "$head" "$behind" "$ahead" "$dirty_count" "$occupied_count" "$pane_count" "$busy_count" "$idle_count" \
    "$match_count" "$mismatch_count" "$artifact_count" "$class" "$action"

  if [[ "$APPLY_ACCEPTED" == "true" && "$class" == "accepted-exact" ]]; then
    stash_and_fast_forward "$worker" "$path" "$branch" "$behind" "accepted-exact"
  fi

  if contains_worker "$worker"; then
    if [[ "$busy_count" != "0" && "$INCLUDE_ACTIVE" != "true" ]]; then
      echo "REFUSE $worker: busy/unknown activity count $busy_count occupied=$occupied_count panes=$pane_count; use --include-active only after stopping/reviewing it"
    elif [[ "$ahead" != "0" ]]; then
      echo "REFUSE $worker: branch has $ahead unique commit(s); review/merge commits before discard"
    elif [[ "$dirty_count" == "0" ]]; then
      if [[ "$behind" != "0" ]]; then
        echo "ACTION $worker: clean ff-only $branch -> $BASE_REF by $behind commit(s)"
        git -C "$path" merge --ff-only "$BASE_REF"
      else
        echo "ACTION $worker: already clean and aligned"
      fi
    else
      stash_and_fast_forward "$worker" "$path" "$branch" "$behind" "reviewed-discard"
    fi
  fi
}

main() {
  REPO="$(cd "$REPO" && pwd)"
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git worktree: $REPO"
  git -C "$REPO" rev-parse --verify --quiet "$BASE_REF" >/dev/null || die "Base ref not found: $BASE_REF"

  if [[ "$FETCH" == "true" ]]; then
    git -C "$REPO" fetch origin --prune || echo "WARN: fetch failed; continuing with local refs" >&2
  fi

  if [[ -z "$EXPORT_DIR" ]]; then
    git_common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
    case "$git_common_dir" in
      /*) ;;
      *) git_common_dir="$REPO/$git_common_dir" ;;
    esac
    EXPORT_DIR="$git_common_dir/codex-backups/dirty-worktree-audit-$TIMESTAMP"
  fi
  mkdir -p "$EXPORT_DIR"

  echo "== Dirty Worktree Audit =="
  echo "repo: $REPO"
  echo "base: $BASE_REF"
  echo "workers: $WORKERS"
  echo "export: $EXPORT_DIR"
  echo "mode: evidence$([[ "$APPLY_ACCEPTED" == "true" ]] && printf '+apply-accepted')$([[ -n "$DISCARD_WORKERS" ]] && printf '+stash-discarded')"
  echo
  printf 'worker branch   head     base worker dirty occupied panes busy idle match mismatch artifacts class/action\n'

  for worker in $WORKERS; do
    scan_worker "$worker"
  done
}

main "$@"
