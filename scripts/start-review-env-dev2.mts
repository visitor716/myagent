/**
 * 为 dev2 worktree（Execution Agent 菜单改动）启动隔离 Review 环境。
 * 复用主仓 reviewApp 的 tunnel/state 模块，行为对齐 reviewApp/environment.ts，
 * 但使用合成任务对象，不读/写生产任务库（该工作未登记任务池）。
 *
 * 运行方式（cwd = /home/zhanxp/projects/tg-agent-gateway）：
 *   set -a; source .env; set +a
 *   npx tsx /home/zhanxp/projects/myagent/scripts/start-review-env-dev2.mts
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import {
  fetchHealth,
  findFreeReviewPort,
  startQuickTunnel,
  stopPidsGracefully,
} from '/home/zhanxp/projects/tg-agent-gateway/src/services/reviewApp/tunnel.js';
import {
  readReviewEnvironmentState,
  writeReviewEnvironmentState,
} from '/home/zhanxp/projects/tg-agent-gateway/src/services/reviewApp/state.js';

const WORKTREE = '/home/zhanxp/worktrees/tg-agent-gateway/dev2';
const TASK_ID = 'execution-agent-menu';
const TITLE = 'Execution Agent 菜单改为 Agent 类型';
const BRANCH = 'dev2';
const HEALTH_TIMEOUT_MS = 120_000;
const TUNNEL_HEALTH_TIMEOUT_MS = 90_000;

function fail(message: string): never {
  throw new Error(message);
}

async function waitForHealth(url: string, timeoutMs: number, label: string): Promise<Record<string, unknown>> {
  const deadline = Date.now() + timeoutMs;
  let lastError = 'no response';
  while (Date.now() < deadline) {
    try {
      const health = await fetchHealth(url, 5_000);
      if (health && health.status === 'ok') return health;
      lastError = health ? `unexpected body: ${JSON.stringify(health)}` : 'non-200 response';
    } catch (error) {
      lastError = String(error);
    }
    await new Promise(resolve => setTimeout(resolve, 2_000));
  }
  return fail(`${label} 健康检查超时：${lastError}`);
}

async function main(): Promise<void> {
  if (!fs.existsSync(path.join(WORKTREE, 'dist/index.js'))) fail('缺少 dist/index.js，请先在 dev2 运行 npm run build');
  if (!fs.existsSync(path.join(WORKTREE, 'webapp/dist/index.html'))) fail('缺少 webapp/dist，请先在 dev2 运行 npm run webapp:build');

  const commit = execFileSync('git', ['-C', WORKTREE, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const shortCommit = commit.slice(0, 7);
  const dataDir = `/tmp/tg-agent-gateway-review-app/${TASK_ID}-${shortCommit}`;
  fs.mkdirSync(path.join(dataDir, 'logs'), { recursive: true });

  // 若已有登记的 review 环境，先停掉（对齐 switched 语义）
  const current = readReviewEnvironmentState();
  if (current) {
    console.log(`[review-dev2] 停止已有 review 环境 task=${current.taskId} commit=${current.shortCommit}`);
    await stopPidsGracefully([current.serverPid, current.tunnelPid ?? 0].filter(pid => pid > 0), 10_000);
  }

  const port = await findFreeReviewPort();
  const stdoutLog = fs.openSync(path.join(dataDir, 'logs', 'server-stdout.log'), 'a');
  const stderrLog = fs.openSync(path.join(dataDir, 'logs', 'server-stderr.log'), 'a');
  const child = spawn('node', ['dist/index.js'], {
    cwd: WORKTREE,
    env: {
      ...process.env,
      TG_AGENT_GATEWAY_REVIEW_MODE: '1',
      TG_AGENT_GATEWAY_REVIEW_TASK_ID: TASK_ID,
      TG_AGENT_GATEWAY_REVIEW_COMMIT: commit,
      RUNNER_MODE: 'mock',
      TASK_QUEUE_AUTORUN: 'false',
      DATABASE_PATH: path.join(dataDir, 'gateway.sqlite'),
      TASK_MESSAGES_PATH: path.join(dataDir, 'task-messages.json'),
      LOG_DIR: path.join(dataDir, 'logs'),
      WEBAPP_PORT: String(port),
    },
    stdio: ['ignore', stdoutLog, stderrLog],
  });
  if (child.pid === undefined) fail('启动 Review Server 失败（未获得进程号）');
  const serverPid = child.pid;
  console.log(`[review-dev2] server pid=${serverPid} port=${port}`);

  let tunnelPid: number | null = null;
  try {
    const localUrl = `http://127.0.0.1:${port}`;
    await waitForHealth(localUrl, HEALTH_TIMEOUT_MS, '本地 Review Server');
    console.log(`[review-dev2] 本地健康检查通过 ${localUrl}`);

    const tunnel = await startQuickTunnel(port, path.join(dataDir, 'logs', 'tunnel.log'));
    tunnelPid = tunnel.pid;
    await waitForHealth(tunnel.url, TUNNEL_HEALTH_TIMEOUT_MS, 'Tunnel');
    console.log(`[review-dev2] tunnel 就绪 ${tunnel.url}`);

    writeReviewEnvironmentState({
      version: 1,
      taskId: TASK_ID,
      title: TITLE,
      commit,
      shortCommit,
      branch: BRANCH,
      worktreePath: WORKTREE,
      dataDir,
      port,
      serverPid,
      tunnelPid,
      tunnelUrl: tunnel.url,
      localUrl,
      startedAt: new Date().toISOString(),
      previous: current
        ? {
            taskId: current.taskId,
            commit: current.commit,
            serverPid: current.serverPid,
            tunnelPid: current.tunnelPid,
            stoppedAt: new Date().toISOString(),
          }
        : undefined,
    });

    console.log(JSON.stringify({ ok: true, tunnelUrl: tunnel.url, localUrl, port, serverPid, tunnelPid, commit, shortCommit }));
  } catch (error) {
    await stopPidsGracefully([serverPid, tunnelPid ?? 0].filter(pid => pid > 0), 3_000);
    throw error;
  }
}

main().catch(error => {
  console.error(`[review-dev2] 失败：${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
