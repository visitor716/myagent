import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { Runner, RunnerInput, RunnerResult } from '../tasks/types.js';
import { logger } from '../utils/logger.js';
import { getEffectiveCwd, formatWorktreeCheck } from './runner.js';

// 示例：CodexRunner 接入模板
// 其他 Runner（ClaudeCodeRunner、HermesRunner、MockRunner等）参考此模式

export class CodexRunner implements Runner {
  async run(input: RunnerInput): Promise<RunnerResult> {
    const startTime = Date.now();

    // 1. 确保日志目录存在
    const runLogDir = path.resolve(process.cwd(), 'logs', 'runs');
    if (!fs.existsSync(runLogDir)) {
      fs.mkdirSync(runLogDir, { recursive: true });
    }
    const logPath = input.logPath ?? path.resolve(runLogDir, `${input.taskId}.log`);

    // 2. 创建日志写入流
    const logStream = fs.createWriteStream(logPath, { flags: 'a' });

    // 3. 获取有效工作目录（核心：接入 resolveRunnerWorkspace）
    const { cwd: effectiveCwd, error: cwdError } = getEffectiveCwd(input);

    // 4. 日志开头输出 Worktree 检查信息
    logStream.write(`${formatWorktreeCheck(input, effectiveCwd)}\n\n`);

    // 5. Worktree 验证失败立即返回错误（禁止 fallback）
    if (cwdError) {
      logStream.write(`Error: ${cwdError}\n`);
      logStream.end();
      return {
        output: `❌ Worktree validation failed: ${cwdError}`,
        exitCode: 1,
        durationMs: Date.now() - startTime,
      };
    }

    try {
      // 6. 使用 effectiveCwd 执行任务
      const result = await this.execCommand(input, effectiveCwd, logStream);

      logStream.end();

      return {
        output: result.output,
        exitCode: result.exitCode,
        durationMs: Date.now() - startTime,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logStream.write(`\nError: ${errorMessage}\n`);
      logStream.end();

      return {
        output: `❌ Execution error: ${errorMessage}`,
        exitCode: 1,
        durationMs: Date.now() - startTime,
      };
    }
  }

  private async execCommand(
    input: RunnerInput,
    cwd: string,
    logStream: fs.WriteStream
  ): Promise<{ output: string; exitCode: number }> {
    // 实现你的命令执行逻辑
    // 确保使用 cwd 作为工作目录

    return new Promise((resolve, reject) => {
      const args = ['your', 'command', 'args'];

      const child = spawn('your-command', args, {
        cwd: cwd, // 使用 effectiveCwd
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (data: Buffer) => {
        const chunk = data.toString('utf-8');
        stdout += chunk;
        logStream.write(chunk);
      });

      child.stderr.on('data', (data: Buffer) => {
        const chunk = data.toString('utf-8');
        stderr += chunk;
        logStream.write(chunk);
      });

      child.on('close', (code: number | null) => {
        resolve({
          output: stdout + stderr,
          exitCode: code ?? 1,
        });
      });

      child.on('error', (error: Error) => {
        reject(error);
      });

      // 写入 prompt
      child.stdin.write(input.prompt);
      child.stdin.end();
    });
  }
}
