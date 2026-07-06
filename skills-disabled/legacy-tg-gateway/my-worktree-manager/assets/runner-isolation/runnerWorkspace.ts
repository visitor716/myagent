import fs from 'node:fs';
import type { RunnerInput } from '../tasks/types.js';

export type RunnerWorkspaceInput = Pick<
  RunnerInput,
  'workspace' | 'effectiveWorkspace' | 'useWorktree' | 'worktreePath'
>;

/**
 * 解析 Runner 执行工作目录
 *
 * 优先级：effectiveWorkspace > worktreePath > workspace
 *
 * 约束：
 * 1. useWorktree=true 时，必须使用 worktreePath/effectiveWorkspace
 * 2. worktreePath 不存在时抛出错误
 * 3. 禁止静默 fallback 到主项目 workspace
 */
export function resolveRunnerWorkspace(input: RunnerWorkspaceInput): string {
  const effectiveWorkspace = normalizePath(input.effectiveWorkspace);
  if (effectiveWorkspace) {
    return assertDirectory(effectiveWorkspace, 'effectiveWorkspace');
  }

  if (input.useWorktree === true) {
    const worktreePath = normalizePath(input.worktreePath);
    if (!worktreePath) {
      throw new Error('useWorktree=true requires worktreePath or effectiveWorkspace');
    }
    return assertDirectory(worktreePath, 'worktreePath');
  }

  const workspace = normalizePath(input.workspace);
  if (!workspace) {
    throw new Error('workspace is required');
  }

  return assertDirectory(workspace, 'workspace');
}

function normalizePath(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function assertDirectory(directoryPath: string, label: string): string {
  if (!fs.existsSync(directoryPath)) {
    throw new Error(`${label} does not exist: ${directoryPath}`);
  }

  if (!fs.statSync(directoryPath).isDirectory()) {
    throw new Error(`${label} is not a directory: ${directoryPath}`);
  }

  return directoryPath;
}
