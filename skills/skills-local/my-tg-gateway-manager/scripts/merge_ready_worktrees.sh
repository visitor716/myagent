#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="/home/zhanxp/projects/tg-agent-gateway"
DEFAULT_WORKERS="cc2 cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10"
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
CANDIDATE_FILE=""
ACTIVITY_SETTLE_SECONDS="${TG_WORKTREE_ACTIVITY_SETTLE_SECONDS:-3}"

READY_WORKERS=()
READY_BRANCHES=()
READY_PATHS=()
READY_EXPECTED_HEADS=()
SKIPPED_LINES=()
CANDIDATE_WORKERS=()
CANDIDATE_BRANCHES=()
CANDIDATE_WORKSPACES=()
CANDIDATE_HEADS=()

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
  --workers "<list>"        Space-separated workers (default: cc2 cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10)
  --candidate-file <path>   Scan only workers approved by a cx2 PASS integration-candidate manifest
  --include-active          Do not skip active worktrees in non-candidate mode
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
  - Candidate mode requires exact manifest worker, workspace, branch, and 40-character HEAD matches,
    and never permits dirty, busy, behind, or diverged candidates.
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
    --candidate-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --candidate-file" >&2; exit 2; }
      CANDIDATE_FILE="$2"
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

parse_candidate_manifest() {
  python3 - "$CANDIDATE_FILE" "$BASE_REF" <<'PY'
import json
import os
import re
import sys

candidate_path, expected_base = sys.argv[1:]

try:
    with open(candidate_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Invalid candidate file: {error}")

if not isinstance(manifest, dict):
    raise SystemExit("Invalid candidate file: root must be an object")
if type(manifest.get("schemaVersion")) is not int or manifest.get("schemaVersion") != 1:
    raise SystemExit("Invalid candidate file: schemaVersion must be 1")
if manifest.get("kind") != "tg-agent-gateway.integration-candidate":
    raise SystemExit("Invalid candidate file: kind must be tg-agent-gateway.integration-candidate")
review = manifest.get("review")
if not isinstance(review, dict) or review.get("status") != "PASS":
    raise SystemExit("Invalid candidate file: review.status must be PASS")
if manifest.get("baseRef") != expected_base:
    raise SystemExit(
        f"Invalid candidate file: baseRef {manifest.get('baseRef')!r} does not match --base {expected_base!r}"
    )

candidates = manifest.get("candidates")
if not isinstance(candidates, list) or not candidates:
    raise SystemExit("Invalid candidate file: candidates must be a non-empty array")

workers = set()
for index, candidate in enumerate(candidates):
    if not isinstance(candidate, dict):
        raise SystemExit(f"Invalid candidate file: candidates[{index}] must be an object")

    worker = candidate.get("worker")
    branch = candidate.get("branch")
    workspace = candidate.get("workspace")
    head = candidate.get("head")
    prefix = f"Invalid candidate file: candidates[{index}]"

    if not isinstance(worker, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", worker):
        raise SystemExit(f"{prefix}.worker is invalid")
    worker_key = worker.casefold()
    if worker_key in workers:
        raise SystemExit(f"Invalid candidate file: duplicate worker {worker}")
    workers.add(worker_key)
    if not isinstance(branch, str) or not branch or any(ord(char) < 32 for char in branch):
        raise SystemExit(f"{prefix}.branch is invalid")
    if not isinstance(workspace, str) or not os.path.isabs(workspace) or any(ord(char) < 32 for char in workspace):
        raise SystemExit(f"{prefix}.workspace must be an absolute path without control characters")
    if not isinstance(head, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", head):
        raise SystemExit(f"{prefix}.head must be a 40-character hexadecimal SHA")

    print("\t".join((worker, branch, os.path.realpath(workspace), head.lower())))
PY
}

load_candidate_manifest() {
  local rows worker branch workspace head

  [[ -f "$CANDIDATE_FILE" ]] || die "Candidate file not found: $CANDIDATE_FILE"
  if ! rows="$(parse_candidate_manifest)"; then
    die "Candidate manifest validation failed: $CANDIDATE_FILE"
  fi

  while IFS=$'\t' read -r worker branch workspace head; do
    [[ -n "$worker" ]] || continue
    git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "Invalid candidate branch for $worker: $branch"
    CANDIDATE_WORKERS+=("$worker")
    CANDIDATE_BRANCHES+=("$branch")
    CANDIDATE_WORKSPACES+=("$workspace")
    CANDIDATE_HEADS+=("$head")
  done <<<"$rows"

  [[ ${#CANDIDATE_WORKERS[@]} -gt 0 ]] || die "Candidate manifest has no usable candidates: $CANDIDATE_FILE"
  CANDIDATE_FILE="$(cd "$(dirname "$CANDIDATE_FILE")" && pwd)/$(basename "$CANDIDATE_FILE")"
}

scan_worker() {
  local worker="$1"
  local expected_path="${2:-}"
  local expected_branch="${3:-}"
  local expected_head="${4:-}"
  local path path_common repo_common branch head status occupied panes busy idle counts behind ahead

  path="${expected_path:-$(worker_path "$worker")}"
  if [[ ! -d "$path" ]]; then
    add_skip "$worker" "missing worktree ($path)"
    return
  fi
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    add_skip "$worker" "path is not a git worktree ($path)"
    return
  fi
  if [[ -n "$expected_path" ]]; then
    path_common="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    repo_common="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [[ -z "$path_common" || "$path_common" != "$repo_common" ]]; then
      add_skip "$worker" "workspace does not belong to repo ($path)"
      return
    fi
  fi

  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    add_skip "$worker" "detached HEAD"
    return
  fi
  if [[ -n "$expected_branch" && "$branch" != "$expected_branch" ]]; then
    add_skip "$worker" "branch mismatch (expected=$expected_branch actual=$branch path=$path)"
    return
  fi

  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$expected_head" && "${head,,}" != "${expected_head,,}" ]]; then
    add_skip "$worker" "HEAD mismatch (expected=$expected_head actual=${head:-unknown} branch=$branch)"
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
  if [[ "$busy" != "0" && ( -n "$CANDIDATE_FILE" || "$INCLUDE_ACTIVE" != "true" ) ]]; then
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
  READY_PATHS+=("$path")
  READY_EXPECTED_HEADS+=("$expected_head")
  echo "READY $worker: branch=$branch ahead=$ahead head=$(short_head "$path") occupied=$occupied busy=$busy idle_panes=$idle"
}

print_summary() {
  echo
  echo "== Summary =="
  echo "repo: $REPO"
  echo "base: $BASE_REF"
  if [[ -n "$CANDIDATE_FILE" ]]; then
    echo "candidate file: $CANDIDATE_FILE"
  fi
  echo "mode: $($APPLY && echo apply || echo dry-run)"
  echo "ready: ${#READY_WORKERS[@]}"
  echo "skipped: ${#SKIPPED_LINES[@]}"

  if [[ ${#SKIPPED_LINES[@]} -gt 0 ]]; then
    echo
    echo "== Skipped =="
    printf '%s\n' "${SKIPPED_LINES[@]}"
  fi
}

assert_candidate_ready_for_merge() {
  local worker="$1"
  local path="$2"
  local expected_branch="$3"
  local expected_head="$4"
  local path_common repo_common branch head status occupied panes busy idle counts behind ahead

  [[ -d "$path" ]] || die "Candidate $worker workspace disappeared before merge: $path"
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Candidate $worker workspace is no longer a git worktree: $path"
  path_common="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  repo_common="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -n "$path_common" && "$path_common" == "$repo_common" ]] || die "Candidate $worker workspace no longer belongs to repo: $path"

  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  [[ "$branch" == "$expected_branch" ]] || die "Candidate $worker branch changed before merge: expected=$expected_branch actual=${branch:-detached}"
  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  [[ "${head,,}" == "${expected_head,,}" ]] || die "Candidate $worker HEAD changed before merge: expected=$expected_head actual=${head:-unknown}"

  status="$(git -C "$path" status --short)"
  [[ -z "$status" ]] || die "Candidate $worker became dirty before merge"

  read -r occupied panes busy idle <<<"$(worktree_activity_summary "$path" "$ACTIVITY_SETTLE_SECONDS")"
  if [[ "$busy" != "0" ]]; then
    die "Candidate $worker became busy before merge: busy=$busy occupied=$occupied panes=$panes"
  fi

  counts="$(git -C "$path" rev-list --left-right --count "$BASE_REF...HEAD" 2>/dev/null)" || die "Cannot compare candidate $worker against $BASE_REF before merge"
  read -r behind ahead <<<"$counts"
  [[ "$ahead" != "0" && "$behind" == "0" ]] || die "Candidate $worker is no longer ready before merge: behind=$behind ahead=$ahead"
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
  local timestamp integration_branch tmp_worktree old_head new_head i branch worker path expected_head merge_target

  if [[ -n "$CANDIDATE_FILE" && ${#READY_WORKERS[@]} -ne ${#CANDIDATE_WORKERS[@]} ]]; then
    die "Candidate batch is not fully ready: ready=${#READY_WORKERS[@]} expected=${#CANDIDATE_WORKERS[@]}"
  fi

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
    path="${READY_PATHS[$i]}"
    expected_head="${READY_EXPECTED_HEADS[$i]}"
    merge_target="$branch"
    if [[ -n "$CANDIDATE_FILE" ]]; then
      assert_candidate_ready_for_merge "$worker" "$path" "$branch" "$expected_head"
      merge_target="$expected_head"
    fi
    echo
    echo "MERGE $worker: $branch -> $integration_branch"
    if ! git -C "$tmp_worktree" merge --no-ff -m "Merge branch '$branch' from $worker" "$merge_target"; then
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

  if [[ -n "$CANDIDATE_FILE" ]]; then
    load_candidate_manifest
  fi

  if [[ "$FETCH" == "true" ]]; then
    git -C "$REPO" fetch origin --prune || echo "WARN: fetch failed; continuing with local refs" >&2
  fi

  echo "== Scan =="
  if [[ -n "$CANDIDATE_FILE" ]]; then
    for i in "${!CANDIDATE_WORKERS[@]}"; do
      scan_worker \
        "${CANDIDATE_WORKERS[$i]}" \
        "${CANDIDATE_WORKSPACES[$i]}" \
        "${CANDIDATE_BRANCHES[$i]}" \
        "${CANDIDATE_HEADS[$i]}"
    done
  else
    for worker in $WORKERS; do
      scan_worker "$worker"
    done
  fi

  print_summary

  if [[ "$APPLY" == "true" ]]; then
    apply_ready_merges
  else
    echo
    echo "Dry-run only. Re-run with --apply to merge ready worktrees."
  fi
}

main "$@"
