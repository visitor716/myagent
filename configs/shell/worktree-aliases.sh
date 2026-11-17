#!/usr/bin/env bash
# shellcheck shell=bash
# 只保留带项目前缀的 cx1-cx5；重新加载时清除旧工位别名。
_myagent_worktree_cd() {
  local target="/home/zhanxp/worktrees/$1"
  if [[ ! -d "$target" ]]; then
    printf 'worktree 不存在: %s\n' "$target" >&2
    return 1
  fi
  builtin cd -- "$target"
}

_myagent_install_worktree_aliases() {
  local name prefix project index
  for name in "${!BASH_ALIASES[@]}"; do
    if [[ "$name" =~ ^((oa|tg|mag|ms)(cc|cx|hm)[0-9]+|(oa|tg|mag|ms)wt|(cc|cx|hm)[0-9]+|am(cx)?[0-9]*|(oa|tg|ma)-cx[0-9]+)$ ]]; then
      unalias "$name"
    fi
  done
  while read -r prefix project; do
    for index in {1..5}; do
      alias "${prefix}-cx${index}=_myagent_worktree_cd ${project}/cx${index}"
    done
  done <<'PROJECTS'
oa oa-fill-assistant
tg tg-agent-gateway
ma myagent
PROJECTS
}

_myagent_install_worktree_aliases
unset -f _myagent_install_worktree_aliases
