#!/usr/bin/env bash
set -euo pipefail

project=""
worker=""
probe="false"

usage() {
  cat <<'USAGE'
Usage:
  collect_worktree_evidence.sh --project <project-path> [--worker <worker-name>] [--probe]

Collects worktree execution evidence for an acceptance audit.
By default this is read-only. --probe creates and removes WORKTREE_VALIDATION_TMP.txt in the selected worktree.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2:-}"
      shift 2
      ;;
    --worker)
      worker="${2:-}"
      shift 2
      ;;
    --probe)
      probe="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$project" ]]; then
  echo "--project is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$project" ]]; then
  echo "Project directory does not exist: $project" >&2
  exit 1
fi

cd "$project"

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" || true
}

section "Project"
run pwd
run git branch --show-current
run git status --short

section "Git Worktrees"
run git worktree list
run git worktree list --porcelain

worktree_path=""
if [[ -n "$worker" ]]; then
  worktree_path="$(git worktree list --porcelain | awk -v worker="$worker" '
    $1 == "worktree" { path=$2 }
    $1 == "branch" && $2 ~ ("refs/heads/wt/" worker "$") { print path; exit }
  ')"
  if [[ -z "$worktree_path" ]]; then
    candidate="/home/zhanxp/worktrees/$(basename "$project")/$worker"
    if [[ -d "$candidate" ]]; then
      worktree_path="$candidate"
    fi
  fi
else
  worktree_path="$(git worktree list --porcelain | awk -v project="$project" '
    $1 == "worktree" && $2 != project { print $2; exit }
  ')"
fi

if [[ -n "$worktree_path" ]]; then
  section "Selected Worktree"
  (
    cd "$worktree_path"
    run pwd
    run git branch --show-current
    run git status --short
    run git rev-parse --show-toplevel
  )
else
  section "Selected Worktree"
  echo "No worker worktree selected or found."
fi

section "Worker Config Search"
if command -v rg >/dev/null 2>&1; then
  run rg -n "useWorktree|worktreePath|worktree" data src
else
  run grep -R "useWorktree\|worktreePath\|worktree" -n data src
fi

section "Database"
run find . -name "*.sqlite" -o -name "*.db"
db_path=""
if [[ -f data/gateway.sqlite ]]; then
  db_path="data/gateway.sqlite"
else
  db_path="$(find . -name "*.sqlite" -o -name "*.db" | head -1 || true)"
fi

if [[ -n "$db_path" ]] && command -v sqlite3 >/dev/null 2>&1; then
  run sqlite3 "$db_path" ".schema tasks"
  run sqlite3 -header -column "$db_path" "select * from tasks order by created_at desc limit 3;"
else
  echo "No sqlite database found or sqlite3 unavailable."
fi

section "Runner CWD Search"
if command -v rg >/dev/null 2>&1; then
  run rg -n "effectiveWorkspace|worktreePath|useWorktree|cwd|workspace|resolveRunnerWorkspace|getEffectiveCwd" src
else
  run grep -R "effectiveWorkspace\|worktreePath\|useWorktree\|cwd\|workspace\|resolveRunnerWorkspace\|getEffectiveCwd" -n src
fi

section "Recent Logs"
run find logs -type f
if [[ -d logs ]]; then
  recent_log="$(find logs -type f | sort | tail -1 || true)"
  if [[ -n "$recent_log" ]]; then
    echo "Recent log: $recent_log"
    run tail -200 "$recent_log"
  fi
  if command -v rg >/dev/null 2>&1; then
    run rg -n "Worktree Check|effectiveWorkspace|worktreePath|cwd|pwd|branch" logs
  else
    run grep -R "Worktree Check\|effectiveWorkspace\|worktreePath\|cwd\|pwd\|branch" -n logs
  fi
fi

if [[ "$probe" == "true" ]]; then
  section "Temporary File Isolation Probe"
  if [[ -z "$worktree_path" ]]; then
    echo "Cannot probe: no worker worktree selected or found." >&2
    exit 1
  fi
  tmp_file="WORKTREE_VALIDATION_TMP.txt"
  (
    cd "$worktree_path"
    printf 'worktree validation\n' > "$tmp_file"
    run git status --short
  )
  (
    cd "$project"
    run ls "$tmp_file"
  )
  (
    cd "$worktree_path"
    rm -f "$tmp_file"
    run git status --short
  )
fi
