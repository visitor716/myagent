---
name: tg-agent-gateway-worktree-acceptance
description: Validate whether tg-agent-gateway workers truly execute inside Git worktrees by checking data/bots.json useWorktree settings, git worktree inventory, runner cwd/effectiveWorkspace chain, and recent logs. Use when asked to verify tg-agent-gateway worktree isolation, worker cwd, effectiveWorkspace/worktreePath, parallel worker isolation, or worktree acceptance.
---

# tg-agent-gateway-worktree-acceptance

Validate that tg-agent-gateway workers are truly executing in Git worktrees, not just configured but still running in the main repo.

## Triggers

- "tg-agent-gateway worktree 没生效"
- "验证 worker 是否使用 worktree"
- "检查 runner cwd / effectiveWorkspace / worktreePath"
- "并行 worker 是否隔离"
- "worktree 验收"

## Overview

This skill performs read-only acceptance validation to determine whether tg-agent-gateway workers are actually running in Git worktrees. It does NOT create, delete, or fix worktrees.

### Pass Criteria

A worker PASSES only when ALL of the following are true:

1. Worker has `useWorktree: true` in `data/bots.json`
2. Git worktree exists at `/home/zhanxp/worktrees/tg-agent-gateway/{workerName}`
3. Recent task logs show `effectiveCwd` or `pwd` in the worktree path (not main repo)
4. The worktree branch matches `wt/{workerName}`

### Partial Pass Criteria

A worker PARTIALLY PASSES when:

- Configuration exists but no log evidence yet (newly enabled)
- Worktree exists but recent tasks still show main repo cwd (transitioning)

### Fail Criteria

A worker FAILS when:

- `useWorktree: false` or missing in config
- Worktree directory doesn't exist
- Logs consistently show main repo `/home/zhanxp/projects/tg-agent-gateway` as cwd

## Execution Steps

### Step 1: Collect Git Worktree Inventory

```bash
cd /home/zhanxp/projects/tg-agent-gateway && git worktree list --porcelain
```

Parse output to build worktree inventory:
- worktree path
- HEAD commit
- branch name

### Step 2: Check Worker Configuration

Read `/home/zhanxp/projects/tg-agent-gateway/data/bots.json`:

For each worker in `bots`:
- Extract `useWorktree` flag
- Extract `workspace` path
- Note workers with `useWorktree: true`

### Step 3: Verify Execution Chain

Check source files for worktree execution logic:

1. **src/services/worktreeService.ts**
   - `getExecutionWorkspace()` - determines effectiveWorkspace
   - `getWorktreePath()` - generates worktree path

2. **src/runners/runnerWorkspace.ts**
   - `resolveRunnerWorkspace()` - resolves final cwd

3. **src/runners/runner.ts**
   - `getEffectiveCwd()` - entry point for cwd resolution

### Step 4: Search Log Evidence

Check recent task logs for worktree execution evidence:

```bash
# Check structured logs for effectiveWorkspace evidence
grep -r "effectiveCwd\|effectiveWorkspace" /home/zhanxp/projects/tg-agent-gateway/logs/runs/ --include="*.log" | tail -30

# Check gateway logs for worktree execution
grep -E "(effectiveCwd|worktreePath|effectiveWorkspace)" /home/zhanxp/projects/tg-agent-gateway/logs/tg-gateway-*.log | tail -50
```

Look for patterns:
- `"effectiveCwd": "/home/zhanxp/worktrees/tg-agent-gateway/{worker}"` → PASS
- `"effectiveCwd": "/home/zhanxp/projects/tg-agent-gateway"` → FAIL (still in main repo)

### Step 5: Generate Acceptance Report

Output format:

```markdown
## tg-agent-gateway Worktree Acceptance Report

### Worktree Inventory
| Worker | Worktree Path | Branch | Exists | Initialized |
|--------|--------------|--------|--------|-------------|
| cx1 | /home/zhanxp/worktrees/tg-agent-gateway/cx1 | wt/cx1 | ✅ | ✅ |
| ... | ... | ... | ... | ... |

### Worker Configuration Status
| Worker | useWorktree | Workspace | Config OK |
|--------|-------------|-----------|-----------|
| cx1 | ✅ true | /home/zhanxp/projects/tg-agent-gateway | ✅ |
| ... | ... | ... | ... |

### Log Evidence (Last 7 Days)
| Worker | Latest Task | effectiveCwd | Status |
|--------|-------------|--------------|--------|
| hm5 | 2026-04-29 | /home/zhanxp/worktrees/tg-agent-gateway/hm5 | ✅ PASS |
| ... | ... | ... | ... |

### Final Verdict
| Worker | Config | Worktree | Logs | Verdict |
|--------|--------|----------|------|---------|
| cx1 | ✅ | ✅ | ✅ | **PASS** |
| cx2 | ✅ | ✅ | ✅ | **PASS** |
| cc3 | ✅ | ✅ | ✅ | **PASS** |
| cc4 | ✅ | ✅ | ✅ | **PASS** |
| hm5 | ✅ | ✅ | ✅ | **PASS** |
| bdcc1 | ✅ | ✅ | ⚠️ (check logs) | **PARTIAL** |
| bdcc2 | ✅ | ✅ | ⚠️ (no recent) | **PARTIAL** |
| ollama6 | ❌ N/A | N/A | N/A | **SKIP** |
| ollama7 | ❌ N/A | N/A | N/A | **SKIP** |
| ccagent2 | ❌ false | N/A | N/A | **SKIP** |

### Summary
- Total Workers: {count}
- PASS: {count} (truly isolated in worktrees)
- PARTIAL: {count} (configured, verify logs)
- FAIL: {count} (not using worktrees)
- SKIP: {count} (not configured for worktree)

### Recommendations
1. For PARTIAL workers: Run a test task and re-verify
2. For FAIL workers: Check why useWorktree is disabled
3. For workers without log evidence: Logs rotate, check `logs/runs/{worker}/` directories
```

## Key Implementation Details

### Execution Directory Chain

1. Task created in `taskManager.createTask()`:
   - Calls `getExecutionWorkspace(botId, config.workspace, config.useWorktree)`
   - Sets `task.effectiveWorkspace`, `task.worktreePath`, `task.worktreeBranch`

2. Task executed in `runner.runTask()`:
   - Runner receives `RunnerInput` with workspace fields
   - Calls `getEffectiveCwd(input)` in `src/runners/runner.ts`
   - Resolves via `resolveRunnerWorkspace()` in `src/runners/runnerWorkspace.ts`
   - Priority: `effectiveWorkspace` > `worktreePath` > `workspace`

3. Runner logs evidence:
   - `HermesRunner` logs: `"effectiveCwd": "...", "worktreePath": "..."`
   - `ClaudeCodeRunner` logs worktree check block
   - `CodexRunner` logs effectiveCwd in metadata

### Worktree Path Convention

- Base: `/home/zhanxp/worktrees/tg-agent-gateway/`
- Worker path: `{base}/{workerName}` (e.g., `/home/zhanxp/worktrees/tg-agent-gateway/cc4`)
- Branch name: `wt/{workerName}` (e.g., `wt/cc4`)

## Notes

- This skill is READ-ONLY. It does not create, modify, or delete worktrees.
- Log evidence is the ultimate source of truth - configuration alone is insufficient.
- Workers without recent tasks may show "PARTIAL" due to lack of log evidence.
- Workers with `useWorktree: false` or no explicit workspace are intentionally skipped.
