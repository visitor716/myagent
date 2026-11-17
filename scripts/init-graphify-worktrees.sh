#!/usr/bin/env bash
set -euo pipefail

# Initialize or update code-only Graphify graphs for Git worktrees.
# Usage:
#   init-graphify-worktrees.sh [repo_or_worktree_path]
# If a git repository/worktree root is given, it discovers all worktrees via
# `git worktree list --porcelain` and runs `graphify update` in each.
# Pass `--single <worktree_path>` to initialize/update only one worktree.

if ! command -v graphify >/dev/null 2>&1; then
  echo "Error: graphify not found in PATH. Install with: uv tool install graphifyy" >&2
  exit 1
fi

if [[ "${1:-}" == "--single" ]]; then
  target="${2:-.}"
  if [[ ! -d "$target" ]]; then
    echo "Error: directory not found: $target" >&2
    exit 1
  fi
  echo "==> Updating code-only graph in: $target"
  (cd "$target" && graphify update .)
  exit 0
fi

repo="${1:-/home/zhanxp/projects/oa-fill-assistant}"
if [[ ! -d "$repo" ]]; then
  echo "Error: repository not found: $repo" >&2
  exit 1
fi

mapfile -t worktrees < <(git -C "$repo" worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}')

if [[ ${#worktrees[@]} -eq 0 ]]; then
  echo "No worktrees found for $repo" >&2
  exit 1
fi

for wt in "${worktrees[@]}"; do
  if [[ -d "$wt" ]]; then
    echo "==> Updating code-only graph in: $wt"
    (cd "$wt" && graphify update .)
  else
    echo "==> Skipping missing worktree: $wt"
  fi
done
