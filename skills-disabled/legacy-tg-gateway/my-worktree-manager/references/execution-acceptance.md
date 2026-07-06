# Execution Acceptance

用于只读验收 Git worktree 隔离是否真正接入 agent/runner 任务执行流。目标不是证明 worktree 存在，而是证明真实 runner task 的进程 cwd/pwd 在 worker worktree。

## 核心判断

PASS 必须有真实执行证据：

- 仅有 `git worktree list` 不够。
- 仅有 worker config 不够。
- 仅有代码路径不够，除非日志或 live verification task 证明 spawned process cwd。
- 最近真实 runner 日志仍显示主仓 cwd 时，最多部分通过。
- `useWorktree=true` 且 worktree path 缺失却 fallback 到主 workspace 时，验收失败。

## 证据流程

从项目根目录执行。

1. baseline：

```bash
pwd
git branch --show-current
git status --short
```

2. worktree inventory：

```bash
git worktree list
git worktree list --porcelain
```

报告 worktree 数量、路径、分支、是否有主项目外 worktree。

3. 检查一个相关 worker worktree：

```bash
cd <worker-worktree>
pwd
git branch --show-current
git status --short
git rev-parse --show-toplevel
```

只有 `pwd` 和 `show-toplevel` 都是 worktree path，且 branch 不是 `master/main`，才算该子项通过。

4. 检查 worker 配置：

```bash
rg -n "useWorktree|worktreePath|worktree" data src
```

识别 `useWorktree=true` 的 workers，确认 worktree path 是否明确且存在。

5. 检查数据库任务记录：

```bash
find . -name "*.sqlite" -o -name "*.db"
sqlite3 <database> ".schema tasks"
sqlite3 -header -column <database> "select id, worker, workspace, branch, use_worktree, worktree_path, worktree_branch, effective_workspace, status, created_at, updated_at from tasks order by created_at desc limit 10;"
```

字段缺失时查询现有字段并报告 gap。重点看 `use_worktree`、`worktree_path`、`worktree_branch`、`effective_workspace`、`base_commit`、`worktree_status`、`branch`。

6. 审计 runner cwd 解析：

```bash
rg -n "effectiveWorkspace|worktreePath|useWorktree|cwd|workspace|resolveRunnerWorkspace|getEffectiveCwd" src
```

确认优先级是：

```text
effectiveWorkspace > worktreePath > workspace
```

确认 `useWorktree=true` 且 worktree path invalid 时会失败，而不是 fallback。

7. 检查最近日志：

```bash
find logs -type f | sort | tail -20
rg -n "Worktree Check|effectiveWorkspace|worktreePath|cwd|pwd|branch" logs
```

强通过信号类似：

```text
=== Worktree Check ===
workspace: /path/to/main/repo
effectiveWorkspace: /path/to/worktrees/project/worker
useWorktree: true
worktreePath: /path/to/worktrees/project/worker
pwd: /path/to/worktrees/project/worker
branch: wt/worker
```

8. 可选临时文件隔离 probe：

仅在用户允许或任务明确需要时执行，结束前必须清理：

```bash
cd <worker-worktree>
echo "worktree validation" > WORKTREE_VALIDATION_TMP.txt
git status --short

cd <main-project>
ls WORKTREE_VALIDATION_TMP.txt

cd <worker-worktree>
rm WORKTREE_VALIDATION_TMP.txt
git status --short
```

预期：主项目没有临时文件，清理后 worker worktree 干净。

## Helper

证据采集：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/collect_worktree_evidence.sh --project <project-path> --worker <worker-name>
```

只有临时文件 probe 可接受时才加：

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/scripts/collect_worktree_evidence.sh --project <project-path> --worker <worker-name> --probe
```

脚本只采集证据；最终判定仍由 agent 负责。

## 报告格式

使用精确结构：

```text
一、Git worktree 状态
- 是否存在 worktree
- worktree 数量
- 路径是否符合预期
- 分支是否独立

二、Worker 配置状态
- 哪些 worker 启用了 useWorktree
- worktreePath 是否存在
- 是否有 worker 配置错误

三、数据库记录状态
- tasks 表是否有 worktree 字段
- 最近任务是否写入 worktree_path/effective_workspace
- 是否仍然缺字段

四、Runner cwd 状态
- runner 是否使用 effectiveWorkspace/worktreePath
- 是否仍然直接使用 workspace
- useWorktree=true 且 worktree 不存在时是否会失败

五、日志验收
- 最近任务日志里的 cwd/pwd 是什么
- 是否已经在 worktree 内执行
- 是否仍然在主项目目录执行

六、隔离验证
- worktree 临时文件是否没有污染主目录
- 验证结果

七、最终结论
1. ✅ 通过：worktree 已真正接入任务执行流程
2. ⚠️ 部分通过：worktree 存在，但某些 worker/任务/日志未完全接入
3. ❌ 未通过：worktree 只是存在，runner 仍在主项目目录执行

八、如果未通过，列出最小修复建议
```

最终结论必须三选一，原样输出其中一条。
