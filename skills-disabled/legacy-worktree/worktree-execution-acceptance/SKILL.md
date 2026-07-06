---
name: worktree-execution-acceptance
description: Use when validating whether Git worktree isolation is truly wired into an agent or runner task execution flow. Focuses on proving the real process cwd/pwd is the worker worktree, not only that worktrees exist. Checks worktree list, worker config, database task records, runner cwd resolution, logs, and an optional temporary-file isolation probe without modifying business code.
metadata:
  short-description: Validate real worktree execution cwd
---

# Worktree Execution Acceptance

Use this skill for acceptance-only audits of Git worktree isolation in agent gateway / multi-worker repositories. The goal is to prove whether task execution actually runs inside a worker worktree.

Do not modify business code. A temporary file probe is allowed only when explicitly requested or clearly part of the acceptance task, and it must be removed before reporting.

## Core Judgment

Passing requires evidence that a real runner task used a worktree as its cwd/pwd.

- Worktree existence alone is insufficient.
- Worker config alone is insufficient.
- Code paths alone are insufficient unless logs or a live verification task proves the spawned process cwd.
- If recent real runner logs still show the main repository as cwd, the result is at best partial.
- If `useWorktree=true` can silently fall back to the main workspace when the worktree path is missing, fail the audit.

## Evidence Workflow

Run commands from the project root unless noted. Prefer `rg` over `grep` when available.

1. Baseline repository state:

```bash
pwd
git branch --show-current
git status --short
```

2. Worktree inventory:

```bash
git worktree list
git worktree list --porcelain
```

Report the number of worktrees, each path, each branch, and whether there are worktrees outside the main project.

3. Inspect one relevant worker worktree:

```bash
cd <worker-worktree>
pwd
git branch --show-current
git status --short
git rev-parse --show-toplevel
```

Pass this subcheck only if `pwd` and `show-toplevel` are the worktree path, and the branch is not `master` or `main`.

4. Check worker configuration:

```bash
rg -n "useWorktree|worktreePath|worktree" data src
# fallback:
grep -R "useWorktree\|worktreePath\|worktree" -n data src | head -100
```

Identify workers with `useWorktree=true`. For each, determine the explicit or computed worktree path and whether it exists.

5. Check database task records:

```bash
find . -name "*.sqlite" -o -name "*.db"
sqlite3 <database> ".schema tasks"
sqlite3 -header -column <database> "select id, worker, workspace, branch, use_worktree, worktree_path, worktree_branch, effective_workspace, status, created_at, updated_at from tasks order by created_at desc limit 10;"
```

If fields are missing, query the fields that exist and report the gap. Look for `use_worktree`, `worktree_path`, `worktree_branch`, `effective_workspace`, `base_commit`, `worktree_status`, or `branch`.

6. Audit runner cwd resolution:

```bash
rg -n "effectiveWorkspace|worktreePath|useWorktree|cwd|workspace|resolveRunnerWorkspace|getEffectiveCwd" src
```

Confirm the runner cwd priority is:

```text
effectiveWorkspace > worktreePath > workspace
```

Confirm `useWorktree=true` with a missing or invalid worktree path fails instead of falling back to the main workspace.

7. Inspect recent logs:

```bash
find logs -type f | sort | tail -20
tail -200 <recent-log-file>
rg -n "Worktree Check|effectiveWorkspace|worktreePath|cwd|pwd|branch" logs
```

Logs must show the real spawned runner cwd/pwd. A strong pass signal looks like:

```text
=== Worktree Check ===
workspace: /path/to/main/repo
effectiveWorkspace: /path/to/worktrees/project/worker
useWorktree: true
worktreePath: /path/to/worktrees/project/worker
pwd: /path/to/worktrees/project/worker
branch: wt/worker
```

If `cwd` or `pwd` is still the main repository in the latest real runner log, do not mark full pass.

8. Optional temporary-file isolation probe:

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

Expected: the main project does not contain the temporary file, and the worktree is clean after cleanup.

## Helper Script

For evidence collection, run:

```bash
bash <skill-dir>/scripts/collect_worktree_evidence.sh --project <project-path> --worker <worker-name> --probe
```

Use `--probe` only when a temporary create/delete check is acceptable. The script collects evidence; the agent still owns interpretation and the final verdict.

## Report Format

Use this exact structure:

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

Final conclusion must use exactly one of the three listed verdict lines.
