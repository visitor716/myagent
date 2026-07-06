# Review Gate

用于 `tg-agent-gateway` worker worktree 或 candidate branch 的只读审查。目标是判断结果是否可以标记为 `cx2 accepted` 或交给 master 集成。

## 禁止事项

- 不编辑文件。
- 不 commit / merge / push。
- 不 reset / checkout away / clean worker worktree。
- 不停止 tmux pane。
- 不在没有工作流授权时标记 task accepted。

## 输入推断

尽量从当前 repo 推断：

- target worktree path
- worker alias 或 branch pattern
- review scope：`single`、`all`、`all-worker`
- parent task / plan
- claimed changed files
- claimed verification commands
- review objective

当 scope 是 `all` 或 `all-worker`，逐个 candidate branch 给出 PASS/FAIL。若多个 worktree 可选且目标不清，输出 `REVIEW: FAIL` 并列出候选。

## 只读证据

优先执行或读取：

```bash
pwd
git status --short
git branch --show-current
git branch --list
git diff --stat
git diff --name-status
git diff
git log --oneline --decorate -n 10
git worktree list --porcelain
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_worker_refs.sh
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_dirty_worktrees.sh
```

同时检查相关 `plans/`、`logs/runs/`、SQLite task 记录或已有验证输出。不要运行昂贵验证，除非用户明确要求；缺验证就标为 evidence gap。

## 判定规则

单分支 PASS 需要同时满足：

- diff 符合任务 scope。
- 没有混入无关 dirty/untracked 变化。
- branch/worktree 身份清楚。
- claimed files 与实际 diff 一致。
- 验证证据存在且相关。
- 未无授权修改 callback_data、task status、workspace、permission mode、worker alias 等敏感语义。
- 未包含 secrets、tokens、logs、`.env` 或运行时生成物。
- master 集成不需要额外产品/架构决策。

任一条件触发 FAIL：

- 目标分支不明确。
- diff 含无关变更。
- dirty state 含未审查文件。
- 代码变更缺验证。
- 实现偏离 cx1 plan 或用户 scope。
- 只改 UI 文案却声称改变后端/runtime 行为。
- runner/task 语义无明确需求却被修改。
- 包含生成文件、日志、密钥。
- merge 需要人工冲突处理或策略决策。

手动验证缺口可标注为 `manual_verification_gap`、`evidence_gap`、`runtime_gap`，但不能伪装成已验证。

## 输出格式

第一行必须是：

```text
REVIEW: PASS
```

或：

```text
REVIEW: FAIL
```

然后使用：

```markdown
## Summary
- ...

## Candidates
- Worktree:
- Scope:
- Workers:

## Branch Review Matrix
- Branch:
  - Worker:
  - Task:
  - Decision:
  - Files changed:
  - In scope:
  - Out of scope:
  - Dirty/untracked state:

## Aggregate Diff Scope
- Files changed:
- In scope:
- Out of scope:
- Dirty/untracked state:

## Verification Evidence
- Commands claimed:
- Evidence found:
- Missing verification:

## Risks
- ...

## Master Integration Recommendation
- Integrate:
- Required action before master:
- Branch-by-branch recommendation:
- Suggested command/path for next reviewer:

## Next Step
- ...
```

整体结果只有所有审查分支 PASS 时才是 `REVIEW: PASS`。
