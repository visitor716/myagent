#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="/home/zhanxp/projects/tg-agent-gateway"
DEFAULT_BASE="master"
DEFAULT_REFS="master wt/cc1 wt/cc2 wt/cc3 wt/cc4 wt/cc5 wt/cc6 wt/cc7 wt/cc8 wt/cc9 wt/cc10 wt/cx1 wt/cx2 wt/cx3 wt/cx4 wt/cx5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/worktree_activity.sh"

REPO="$DEFAULT_REPO"
BASE_REF="$DEFAULT_BASE"
REFS="$DEFAULT_REFS"
FETCH=true
ACTIVITY_SETTLE_SECONDS="${TG_WORKTREE_ACTIVITY_SETTLE_SECONDS:-3}"

usage() {
  cat <<'EOF'
Usage: audit_worker_refs.sh [options]

Read-only audit for tg-agent-gateway active worker branches and worktrees.

Options:
  --repo <path>      Main repo path (default: /home/zhanxp/projects/tg-agent-gateway)
  --base <ref>       Base branch/ref (default: master)
  --refs "<list>"    Space-separated refs to audit
  --activity-settle-seconds <n>
                     Seconds to sample tmux output before treating a pane as idle (default: 3)
  --no-fetch         Skip git fetch origin --prune
  -h, --help         Show this help
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
    --refs)
      [[ $# -ge 2 ]] || { echo "Missing value for --refs" >&2; exit 2; }
      REFS="$2"
      shift 2
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

short_ref() {
  git -C "$REPO" rev-parse --verify --short "$1" 2>/dev/null || true
}

worker_path_for_ref() {
  local ref="$1"
  local repo_name worker

  if [[ "$ref" == "$BASE_REF" || "$ref" == "master" ]]; then
    printf '%s\n' "$REPO"
    return
  fi

  if [[ "$ref" == wt/* ]]; then
    worker="${ref#wt/}"
    repo_name="$(basename "$REPO")"
    printf '%s\n' "$(cd "$REPO/../.." && pwd)/worktrees/$repo_name/$worker"
    return
  fi

  printf '\n'
}

REPO="$(cd "$REPO" && pwd)"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git worktree: $REPO"

if [[ "$FETCH" == "true" ]]; then
  git -C "$REPO" fetch origin --prune >/dev/null
fi

base_short="$(short_ref "$BASE_REF")"
origin_base_short="$(short_ref "origin/$BASE_REF")"

echo "== Repo =="
echo "repo: $REPO"
echo "base: $BASE_REF local=$base_short remote=$origin_base_short"
echo
echo "== Active Refs =="

for ref in $REFS; do
  local_short="$(short_ref "$ref")"
  remote_short="$(short_ref "origin/$ref")"
  counts="n/a"
  path="$(worker_path_for_ref "$ref")"
  status="missing"
  dirty=0
  occupied=0
  panes=0
  busy=0
  idle=0

  if [[ -n "$local_short" && -n "$remote_short" ]]; then
    counts="$(git -C "$REPO" rev-list --left-right --count "origin/$ref...$ref")"
  fi

  if [[ -n "$path" && -d "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    status="clean"
    dirty="$(git -C "$path" status --short | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$ref" == "$BASE_REF" || "$ref" == "master" ]]; then
      occupied="n/a"
      panes="n/a"
      busy="n/a"
      idle="n/a"
    else
      read -r occupied panes busy idle <<<"$(worktree_activity_summary "$path" "$ACTIVITY_SETTLE_SECONDS")"
    fi
    if [[ "$dirty" != "0" ]]; then
      status="dirty"
    elif [[ "$busy" != "0" && "$busy" != "n/a" ]]; then
      status="busy"
    elif [[ "$occupied" != "0" && "$occupied" != "n/a" ]]; then
      status="idle-occupied"
    fi
  fi

  printf '%-8s local=%-8s remote=%-8s counts=%-5s worktree=%s dirty=%s occupied=%s panes=%s busy=%s idle_panes=%s\n' \
    "$ref" "${local_short:-missing}" "${remote_short:-missing}" "$counts" "$status" "$dirty" "$occupied" "$panes" "$busy" "$idle"
done

echo
echo "== Local Heads Not At $BASE_REF =="
git -C "$REPO" for-each-ref refs/heads --format='%(refname:short) %(objectname:short)' |
  awk -v base="$base_short" '$2 != base { print }' || true

echo
echo "== Origin Heads Not At origin/$BASE_REF =="
git -C "$REPO" for-each-ref refs/remotes/origin --format='%(refname:short) %(objectname:short)' |
  awk -v base="$origin_base_short" '$1 != "origin/HEAD" && $2 != base { print }' || true
