# Merge Master

用于把已接受的 `tg-agent-gateway` worker worktree/branch 安全集成到本地 `master`，验证、重启 Gateway/WebApp、发送最新 `/app` 给 Telegram bot 进行手机自测，然后按用户要求 push/sync/清理 worker refs。

## 常用 lane

- **Merge-to-master**：合并 ready worker commits 到本地 `master`，验证、重启、发 `/app`。
- **Accepted patch**：Codex 已把 reviewed worker diff 应用到主 checkout，但还未 commit 或处置 worker。
- **Completed dirty worker**：worker 停止输出但 worktree dirty；审查后接受最佳 patch 或保留/备份废弃变体。
- **Dirty audit**：同步前分类 dirty worker 为 `accepted-exact`、`keep-review`、`reviewed-discard`。
- **Push/sync**：手机自测接受后 push `master`，快进 active worker/planner/reviewer branches。
- **Master-only push**：只推 docs/plans/evidence 等 master-only commit，不重启不发 `/app`。
- **Cleanup**：合并同步完成后关闭已完成的 Claude worker tmux session。

## Standing Preference

用户在 `/home/zhanxp/projects/tg-agent-gateway` 说 `merge` / `合并` / `发版` 且上下文是 accepted worker work 时，直接继续本地 merge lane：

1. 在 `master` 做最终验证。
2. 重启 Gateway/WebApp。
3. 发送最新 `/app` WebApp entry 给 Telegram bot。
4. 让用户从 fresh App button 手机自测。
5. 未明确说 `push` / `finalize` / 发布前，不 push。

手机自测接受后：

1. fast-forward push `master`。
2. 快进 clean active worker/planner/reviewer branches 到 `master`。
3. 只 push clean 且 non-diverged active refs。
4. fetch/prune 并审计 local/remote ahead-behind 为 `0 0`。
5. 关闭已完成且已合并的 `claude-cc*` tmux sessions。

## Quick Start

总是先 dry-run：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/merge_ready_worktrees.sh --dry-run
```

只读 refs 审计：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_worker_refs.sh
```

dirty worker 分类：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_dirty_worktrees.sh
```

确认 dry-run 后再 apply：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/merge_ready_worktrees.sh --apply
```

默认 worker scan order：

```text
cc2 cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10
```

默认 active branch set：

```text
master wt/cc1 wt/cc2 wt/cc3 wt/cc4 wt/cc5 wt/cc6 wt/cc7 wt/cc8 wt/cc9 wt/cc10 wt/cx1 wt/cx2 wt/cx3 wt/cx4 wt/cx5
```

## 安全规则

脚本只在以下条件同时满足时标记 worker ready：

- worktree 存在且是 Git worktree。
- worktree 无 uncommitted changes。
- 没有 busy/unknown local activity，除非显式 `--include-active`。
- worker branch ahead of `master`。
- worker branch not behind `master`。

跳过 dirty、busy、unchanged、behind、diverged、missing、invalid worktrees，并报告原因。tmux/Codex/Claude pane cwd 仍在 worktree 内只代表 occupied；如果 settle window 内输出无变化，不一定阻塞 clean branch merge。

禁止默认使用：

- `git reset --hard`
- `git clean`
- force push
- 覆盖或 stash 无关用户工作
- 手机自测前自动 push

例外必须很窄：accepted duplicate diff 可先导出 patch 再 stash；特定 worker branch 可在用户要求处理且已备份时 reset 到 `master`；force-with-lease 只允许命名远端 worker branch 且使用精确 old SHA。

## Accepted Patch Lane

当主 checkout dirty 其实是已接受 worker patch 时，不要直接当 blocker。先证明来源和 scope：

```bash
git -C /home/zhanxp/projects/tg-agent-gateway status --short
git -C /home/zhanxp/projects/tg-agent-gateway diff --stat
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 status --short
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 diff --stat
```

流程：

1. 只 commit accepted files，保留无关 dirty/untracked。
2. 尽量 commit 前运行最终验证。
3. 用 Lore commit protocol 写 commit。
4. 清 worker duplicate diff 前先备份：

```bash
ts=$(date +%Y%m%d-%H%M%S)
worker=cc2
git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker diff --binary \
  > /tmp/tg-agent-gateway-$worker-accepted-before-ff-$ts.patch
git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker stash push -u \
  -m "backup $worker accepted duplicate before ff master $ts"
git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker merge --ff-only master
```

5. 继续 restart `/app` 手机自测 lane。

如果主 diff 无法与无关变更分离，停止并报告 blocker。

## Dirty Audit Lane

dirty worker refs 同步前先分类：

- `accepted-exact`：dirty 内容已等价于 `master` 且无 unique commits，可备份/stash/ff-only。
- `keep-review`：内容不同、有 unique commits、或仍 busy/unknown，保留待审。
- `reviewed-discard`：确认过期或被替代，命名 worker 后备份/stash。

只自动处理 accepted-exact：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_dirty_worktrees.sh --apply-accepted
```

reviewed discard 必须显式列 worker：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_dirty_worktrees.sh --stash-discarded "cc2 cc3"
```

## Cleanup

关闭 completed worker tmux session 前先 dry-run：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3"
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3" --apply
```

不要关闭 `tg-agent-gateway`、`tg-webapp-dev`、`tg-webapp-tunnel`、main `codex*` 或无关 `claude*` session。

## 报告

最终报告包含：

- merged/ready/skipped workers 与原因。
- verification command/result。
- `master` HEAD before/after。
- 若失败，integration worktree path。
- dirty classification、backup patch/stash/branch paths。
- pushed refs 或明确跳过原因。
