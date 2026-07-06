---
name: my-worktree-manager
description: Unified manager for tg-agent-gateway Git worktree workflows. Use when Codex needs to review worker worktrees or candidate branches, merge accepted worker work into master, sync/push/clean worker refs, implement or repair runner worktree isolation, or validate that real task execution cwd/pwd is inside a worktree. Replaces the separate worktree-execution-acceptance, worktree-merge-master, worktree-runner-isolation, and my-worktree-review workflows.
---

# My Worktree Manager

统一处理 `tg-agent-gateway` 的 worktree 审查、master 合并、runner 隔离接入和执行验收。默认项目路径：

```text
/home/zhanxp/projects/tg-agent-gateway
```

## 路由

先判断用户要的是哪条 lane，再只加载对应 reference：

- **Review lane**：审查 worker/candidate branch，判断能不能进入 master。读取 `references/review-gate.md`。
- **Merge lane**：已接受 worktree 结果合并到 `master`、验证、重启、发 `/app`、push/sync/清理。读取 `references/merge-master.md`。
- **Runner isolation lane**：实现或修复任务执行 cwd 隔离，让 runner 真正在 worktree 执行。读取 `references/runner-isolation.md`。
- **Acceptance lane**：只做验收，证明真实任务进程 cwd/pwd 是否在 worktree。读取 `references/execution-acceptance.md`。

如果用户只说 `merge`、`push`、`发版`、`同步分支`，优先走 Merge lane。
如果用户说 `review`、`审查`、`能不能合并`，优先走 Review lane。
如果用户说 `隔离运行`、`runner cwd`、`useWorktree`，优先走 Runner isolation lane。
如果用户说 `验收`、`执行验收`、`证明真的在 worktree`，优先走 Acceptance lane。

## 通用规则

- 保护用户 worktree：不要 reset/clean/force push/删除分支，除非用户明确要求且先备份。
- Review 和 Acceptance lane 默认只读；不要修改代码、提交、合并或清理 worker。
- Merge lane 先 dry-run/audit，再 apply；遇到 dirty、busy、behind、diverged、验证失败就停下报告证据。
- Runner isolation lane 可以改代码，但必须先锁定成功标准：`effectiveWorkspace > worktreePath > workspace`，且 `useWorktree=true` 不允许 fallback 到主仓。
- 优先使用本 skill 自带脚本路径：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/audit_worker_refs.sh
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/audit_dirty_worktrees.sh
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/merge_ready_worktrees.sh --dry-run
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/collect_worktree_evidence.sh --project /home/zhanxp/projects/tg-agent-gateway --worker cc3
```

## Bundled Resources

- `scripts/merge_ready_worktrees.sh`：扫描并合并 ready worker branches。
- `scripts/audit_worker_refs.sh`：只读审计 active worker refs。
- `scripts/audit_dirty_worktrees.sh`：分类 dirty worker worktrees 并导出证据。
- `scripts/worktree_activity.sh`：判断 worktree 是否仍有本地活动。
- `scripts/cleanup_completed_worker_tmux.sh`：安全关闭已合并的 completed worker tmux session。
- `scripts/collect_worktree_evidence.sh`：执行验收证据采集。
- `assets/runner-isolation/`：runner cwd 隔离接入模板。
