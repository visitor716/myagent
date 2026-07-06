# Runner Isolation

用于实现或修复多 Agent runner 执行目录隔离。目标是让每个 task 真正在独立 Git worktree 中执行，避免污染主项目目录。

## 核心约束

CWD 优先级必须是：

```text
effectiveWorkspace > worktreePath > workspace
```

规则：

1. `effectiveWorkspace` 存在时优先使用。
2. `useWorktree=true` 时必须使用 `worktreePath` 或 `effectiveWorkspace`。
3. `useWorktree=true` 且 worktree 路径缺失/不存在时任务必须失败。
4. 禁止静默 fallback 到主项目 `workspace`。
5. 任务日志开头必须输出 `=== Worktree Check ===`，包含 workspace、effectiveWorkspace、useWorktree、worktreePath、worktreeBranch、pwd。

## 可复用模板

模板在：

```text
/home/zhanxp/projects/myagent/skills/skills-local/my-worktree-manager/assets/runner-isolation/
```

文件用途：

- `runnerWorkspace.ts`：CWD 解析核心。
- `runner.ts.template`：runner 统一入口模板。
- `codexRunner.template.ts`：具体 runner 接入示例。
- `worktreeService.ts.template`：worktree 路径计算、初始化、状态检查示例。

## 接入步骤

1. 更新 Task/RunnerInput 类型：

```typescript
export interface Task {
  useWorktree?: boolean;
  worktreePath?: string;
  worktreeBranch?: string;
  effectiveWorkspace?: string;
}
```

2. 添加 SQLite 字段：

```sql
ALTER TABLE tasks ADD COLUMN use_worktree INTEGER DEFAULT 0;
ALTER TABLE tasks ADD COLUMN worktree_path TEXT;
ALTER TABLE tasks ADD COLUMN worktree_branch TEXT;
ALTER TABLE tasks ADD COLUMN effective_workspace TEXT;
```

3. 更新 DB 字段映射：

```typescript
useWorktree: 'use_worktree',
worktreePath: 'worktree_path',
worktreeBranch: 'worktree_branch',
effectiveWorkspace: 'effective_workspace',
```

4. TaskManager 在 runner input 之前解析/确保 worktree：

```typescript
const workspaceContext = getExecutionWorkspace(
  task.workerName,
  task.workspace,
  task.useWorktree ?? false
);

task.effectiveWorkspace = workspaceContext.effectiveWorkspace;
task.useWorktree = workspaceContext.useWorktree;
task.worktreePath = workspaceContext.worktreePath;
task.worktreeBranch = workspaceContext.worktreeBranch;
```

5. Runner 调用 cwd resolver，并在执行前写入检查日志：

```typescript
const { cwd: effectiveCwd, error: cwdError } = getEffectiveCwd(input);
logStream.write(formatWorktreeCheck(input, effectiveCwd) + '\n\n');

if (cwdError) {
  return {
    output: `Worktree validation failed: ${cwdError}`,
    exitCode: 1,
    durationMs: 0,
  };
}
```

## 验收标准

- 数据库任务记录包含 worktree 字段。
- `use_worktree=1` 的任务记录了 `worktree_path`、`worktree_branch`、`effective_workspace`。
- runner 日志开头输出 `=== Worktree Check ===`。
- 日志中的 `pwd` 是 worker worktree path，不是主项目目录。
- worktree 缺失时任务失败，不 fallback。
- Acceptance lane 能用真实任务日志证明 cwd/pwd。

## 常见问题

任务仍在主项目目录执行时检查：

1. `data/bots.json` 是否配置 `useWorktree=true`。
2. TaskManager 是否调用 worktree service。
3. RunnerInput 是否传递了 worktree 字段。
4. runner 是否使用 resolver 的 cwd 执行子进程。

worktree 路径不存在但任务未失败时检查：

1. resolver 是否 assert directory。
2. runner 是否在 `cwdError` 时立即返回失败。
3. 是否存在旧 fallback 代码。
