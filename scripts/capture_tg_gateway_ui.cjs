const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('/home/zhanxp/projects/tg-agent-gateway/node_modules/playwright');

const endpoint = process.env.WS_ENDPOINT;
const targetUrl = process.env.TARGET_URL;
const outputDir = process.env.OUTPUT_DIR;
const sourceCommit = process.env.SOURCE_COMMIT || '2c854b5651ce7a78071f08581a71dfacd31e1acc';

if (!endpoint || !targetUrl || !outputDir) {
  throw new Error('WS_ENDPOINT, TARGET_URL and OUTPUT_DIR are required');
}

const now = new Date('2026-08-26T04:30:00.000Z');
const iso = offsetMinutes => new Date(now.getTime() - offsetMinutes * 60_000).toISOString();
const currentProject = {
  key: 'tg-agent-gateway',
  name: 'TG Agent Gateway',
  path: '/home/zhanxp/projects/tg-agent-gateway',
  type: 'git',
  isCurrent: true,
  available: true,
  validGit: true,
};
const projects = [
  currentProject,
  {
    key: 'myagent',
    name: 'My Agent',
    path: '/home/zhanxp/projects/myagent',
    type: 'git',
    isCurrent: false,
    available: true,
    validGit: true,
  },
  {
    key: 'offline-demo',
    name: '离线示例项目',
    path: '/home/zhanxp/projects/offline-demo',
    type: 'git',
    isCurrent: false,
    available: false,
    validGit: false,
  },
];

function task(overrides) {
  return {
    id: 'task-ui-base',
    title: '示例任务',
    project: 'tg-agent-gateway',
    projectRoot: currentProject.path,
    submitWorkspace: currentProject.path,
    effectiveWorkspace: currentProject.path,
    status: 'pending',
    worker: 'cc4',
    cliTool: 'claude-code',
    priority: 'normal',
    createdAt: iso(25),
    updatedAt: iso(5),
    prompt: '完成一个用于 UI 盘点的示例任务，不修改真实数据。',
    acceptanceCriteria: '页面展示清晰，任务状态与执行上下文可读。',
    workspace: currentProject.path,
    branch: 'master',
    useWorktree: true,
    plannerAgent: 'cx1',
    recommendedAgent: 'cc4',
    lifecycle: {
      attemptedWorkers: [{ workerAlias: 'cc4', available: true, reason: 'selected' }],
      selectedWorker: 'cc4',
      queueReason: '按 Execution Agent 选择执行 worker',
      effectiveWorkspace: currentProject.path,
      worktreeBranch: 'master',
      canAccept: false,
      workflowStage: 'worker_execute',
      routePlan: {
        worker: 'cc4',
        targetBranch: 'master',
        worktreePath: currentProject.path,
        baseHead: '2c854b5',
        conflictGroup: 'ui-inventory',
        riskLevel: 'low',
        routeReason: 'UI inventory synthetic data',
      },
    },
    ...overrides,
  };
}

const runningTask = task({
  id: 'task-ui-running',
  title: '优化 Telegram WebApp 移动端任务列表',
  status: 'running',
  worker: 'cc4',
  branch: 'wt/cc4-task-ui-running',
  worktreeBranch: 'wt/cc4-task-ui-running',
  effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/cc4-task-ui-running',
  startedAt: iso(18),
  lastOutput: '正在执行移动端布局检查与任务卡片验证。',
  lifecycle: {
    attemptedWorkers: [{ workerAlias: 'cc4', available: true, reason: 'selected' }],
    selectedWorker: 'cc4',
    queueReason: '显式选择 Claude Code worker',
    effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/cc4-task-ui-running',
    worktreeBranch: 'wt/cc4-task-ui-running',
    canAccept: false,
    workflowStage: 'worker_execute',
    routePlan: {
      worker: 'cc4',
      targetBranch: 'wt/cc4-task-ui-running',
      worktreePath: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/cc4-task-ui-running',
      baseHead: '2c854b5',
      conflictGroup: 'webapp-ui',
      riskLevel: 'low',
      routeReason: '显式 Agent + 独立 worktree',
    },
  },
});

const reviewTask = task({
  id: 'task-ui-review',
  title: '新增 Qoder Execution Agent 选择入口',
  status: 'pending_review',
  worker: 'qoder1',
  cliTool: 'qoder',
  branch: 'wt/qoder1-task-ui-review',
  worktreeBranch: 'wt/qoder1-task-ui-review',
  effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-review',
  startedAt: iso(45),
  finishedAt: iso(8),
  resultSummary: 'Qoder Registry、任务路由和真实执行链路已完成验证。\n\n### Changed Files\n- webapp/src/components/new-task/ExecutionConfigMenu.tsx\n- src/runners/qoderRunner.ts\n\n### Verification\n- type-check PASS\n- unit tests PASS\n- build PASS',
  verificationSummary: 'type-check、unit、integration、build 全部通过',
  proofNotes: '日志确认实际执行者为 QoderRunner → qoderclicn，无 fallback。',
  reviewSummary: '等待手机端确认 Execution Agent 菜单和任务详情展示。',
  reviewGaps: '请在手机端确认 Agent、worktree 和状态字段可读。',
  planPath: 'plans/cx1/2026-08-26/qoder-execution-agent.md',
  lifecycle: {
    attemptedWorkers: [{ workerAlias: 'qoder1', available: true, reason: 'explicit_worker' }],
    selectedWorker: 'qoder1',
    queueReason: '用户显式选择 Qoder',
    effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-review',
    worktreeBranch: 'wt/qoder1-task-ui-review',
    reviewStatus: 'pending',
    reviewWorker: 'cx2',
    canAccept: true,
    verificationSummary: 'type-check、unit、integration、build 全部通过',
    proofNotes: 'QoderRunner → qoderclicn，exit code 0',
    reviewSummary: '待人工验收',
    reviewGaps: '确认手机端 UI 信息完整',
    workflowStage: 'pending_review',
    candidateCommitSha: 'b5b7ee2a1d6d428e151107ce7df344207440bad3',
    canNextStep: true,
    routePlan: {
      worker: 'qoder1',
      targetBranch: 'wt/qoder1-task-ui-review',
      worktreePath: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-review',
      baseHead: '2c854b5',
      conflictGroup: 'agent-registry',
      riskLevel: 'medium',
      routeReason: '用户显式选择 Qoder Execution Agent',
    },
  },
});

const queuedTask = task({
  id: 'task-ui-queued',
  title: '生成 WebApp UI 页面清单与截图包',
  status: 'queued',
  worker: 'codex1',
  cliTool: 'codex',
  branch: 'wt/codex1-task-ui-queued',
  createdAt: iso(12),
  updatedAt: iso(12),
  lifecycle: {
    attemptedWorkers: [{ workerAlias: 'codex1', available: true, reason: 'queued' }],
    selectedWorker: 'codex1',
    queueReason: '等待当前任务释放 workspace lock',
    effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/codex1-task-ui-queued',
    worktreeBranch: 'wt/codex1-task-ui-queued',
    canAccept: false,
    workflowStage: 'queued',
    routePlan: {
      worker: 'codex1',
      targetBranch: 'wt/codex1-task-ui-queued',
      worktreePath: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/codex1-task-ui-queued',
      baseHead: '2c854b5',
      conflictGroup: 'docs-ui',
      riskLevel: 'low',
      routeReason: '截图任务排队等待执行',
    },
  },
});

const acceptedTask = task({
  id: 'task-ui-accepted',
  title: '修复 iOS Telegram 输入框重复抬升',
  status: 'accepted',
  worker: 'codex1',
  cliTool: 'codex',
  branch: 'wt/keyboard-runtime-fix-20260825',
  startedAt: iso(160),
  finishedAt: iso(95),
  resultSummary: '真机验收通过，输入框保持在可视视口底部。',
  verificationSummary: 'iPhone Telegram 真机验收通过',
  planPath: 'plans/cx1/2026-08-25/ios-keyboard.md',
  lifecycle: {
    attemptedWorkers: [{ workerAlias: 'codex1', available: true, reason: 'selected' }],
    selectedWorker: 'codex1',
    effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/review-keyboard',
    worktreeBranch: 'wt/keyboard-runtime-fix-20260825',
    reviewStatus: 'passed',
    reviewWorker: 'cx2',
    canAccept: false,
    verificationSummary: '真机验收通过',
    workflowStage: 'accepted',
    candidateCommitSha: '181b0d1bdb565c432b3b513249949348060c6191',
    routePlan: {
      worker: 'codex1',
      targetBranch: 'wt/keyboard-runtime-fix-20260825',
      worktreePath: '/home/zhanxp/worktrees/tg-agent-gateway/review-keyboard',
      baseHead: '5dba058',
      conflictGroup: 'ios-keyboard',
      riskLevel: 'medium',
      routeReason: 'iOS Telegram 真机修复',
    },
  },
});

const failedTask = task({
  id: 'task-ui-failed',
  title: '验证过期 Quick Tunnel 链路',
  status: 'failed',
  worker: 'cc5',
  createdAt: iso(210),
  updatedAt: iso(180),
  failureReason: 'Quick Tunnel 已过期，无法访问公网 URL。',
  errorSummary: 'cloudflared tunnel disconnected',
  lifecycle: {
    attemptedWorkers: [{ workerAlias: 'cc5', available: false, reason: 'tunnel_unavailable' }],
    selectedWorker: 'cc5',
    effectiveWorkspace: currentProject.path,
    worktreeBranch: 'master',
    canAccept: false,
    workflowStage: 'failed',
  },
});

const tasks = [runningTask, reviewTask, queuedTask, acceptedTask, failedTask];
const taskById = new Map(tasks.map(item => [item.id, item]));
const stats = {
  total: tasks.length,
  running: 1,
  pending: 1,
  pendingReview: 1,
  accepted: 1,
  failed: 1,
  bug: 0,
  messages: 3,
};

const messages = [
  {
    taskId: reviewTask.id,
    title: reviewTask.title,
    worker: reviewTask.worker,
    status: reviewTask.status,
    summary: reviewTask.verificationSummary,
    nextStep: '在手机端打开任务详情并完成人工验收',
    isRead: false,
    createdAt: iso(10),
    updatedAt: iso(8),
    readAt: null,
  },
  {
    taskId: failedTask.id,
    title: failedTask.title,
    worker: failedTask.worker,
    status: failedTask.status,
    summary: failedTask.errorSummary,
    nextStep: '重新启动 tunnel 后再验证',
    isRead: false,
    createdAt: iso(185),
    updatedAt: iso(180),
    readAt: null,
  },
  {
    taskId: acceptedTask.id,
    title: acceptedTask.title,
    worker: acceptedTask.worker,
    status: acceptedTask.status,
    summary: acceptedTask.verificationSummary,
    nextStep: '已验收，无需操作',
    isRead: true,
    createdAt: iso(100),
    updatedAt: iso(95),
    readAt: iso(90),
  },
];

const displayEvents = [
  { id: 'event-1', taskId: reviewTask.id, type: 'task_created', title: '任务已创建', message: '已创建独立 worktree', command: null, status: 'success', createdAt: iso(44) },
  { id: 'event-2', taskId: reviewTask.id, type: 'worker_selected', title: 'Worker 已选择', message: 'Qoder / qoder1', command: null, status: 'success', createdAt: iso(43) },
  { id: 'event-3', taskId: reviewTask.id, type: 'test_passed', title: '自动验证通过', message: 'type-check、unit、integration、build PASS', command: 'npm run ci', status: 'success', createdAt: iso(9) },
  { id: 'event-4', taskId: reviewTask.id, type: 'pending_review', title: '等待人工验收', message: '任务已进入 pending_review', command: null, status: 'info', createdAt: iso(8) },
];

const agentEvents = [
  { id: 'agent-1', taskId: reviewTask.id, seq: 1, createdAt: iso(42), provider: 'qoder', kind: 'reasoning', content: '检查 Agent Registry、任务路由和 worktree 配置。' },
  { id: 'agent-2', taskId: reviewTask.id, seq: 2, createdAt: iso(25), provider: 'qoder', kind: 'tool_start', content: 'npm run type-check && npm run test:unit' },
  { id: 'agent-3', taskId: reviewTask.id, seq: 3, createdAt: iso(8), provider: 'qoder', kind: 'result', content: reviewTask.resultSummary },
  { id: 'agent-4', taskId: reviewTask.id, seq: 4, createdAt: iso(8), provider: 'qoder', kind: 'done', content: 'exit code 0' },
];

const terminalEvents = [
  { id: 'terminal-1', taskId: reviewTask.id, seq: 1, createdAt: iso(25), source: 'runner', kind: 'text', content: '[qoder1] cwd=/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-review' },
  { id: 'terminal-2', taskId: reviewTask.id, seq: 2, createdAt: iso(8), source: 'runner', kind: 'done', content: 'Process exited with code 0' },
];

function filteredTasks(url) {
  const status = url.searchParams.get('status');
  if (!status) return tasks;
  const allowed = new Set(status.split(','));
  return tasks.filter(item => allowed.has(item.status));
}

async function fulfillJson(route, data, status = 200) {
  await route.fulfill({
    status,
    contentType: 'application/json; charset=utf-8',
    headers: {
      'X-TG-Session': 'ui-inventory-session',
      'Cache-Control': 'no-store',
    },
    body: JSON.stringify(data),
  });
}

async function handleApi(route, unknownApiPaths) {
  const request = route.request();
  const url = new URL(request.url());
  const pathname = url.pathname;

  if (pathname === '/api/webapp-probe') {
    await route.fulfill({ status: 204, body: '' });
    return;
  }
  if (pathname === '/api/webapp/projects') {
    await fulfillJson(route, { currentProject, projects });
    return;
  }
  if (pathname === '/api/webapp/projects/current') {
    await fulfillJson(route, { currentProject, projects });
    return;
  }
  if (pathname === '/api/app/overview' || pathname === '/api/webapp/dashboard') {
    await fulfillJson(route, {
      currentProject,
      stats,
      recentTasks: tasks,
      runningTasks: [runningTask],
      pendingReviewTasks: [reviewTask],
      recentMessages: [reviewTask, failedTask, acceptedTask],
    });
    return;
  }
  if (pathname === '/api/webapp/tasks/changes') {
    await fulfillJson(route, { tasks, total: tasks.length, since: null, serverTime: now.toISOString() });
    return;
  }
  if (pathname === '/api/webapp/tasks') {
    const selected = filteredTasks(url);
    await fulfillJson(route, { tasks: selected, total: selected.length });
    return;
  }
  if (pathname === '/api/app/messages') {
    await fulfillJson(route, { unreadCount: 2, messages });
    return;
  }
  if (pathname.startsWith('/api/app/messages/')) {
    await fulfillJson(route, { success: true, message: messages[0], markedCount: 2 });
    return;
  }
  if (pathname === '/api/webapp/workers') {
    await fulfillJson(route, { workers: [
      { id: 'codex1', displayName: 'Codex', type: 'codex', permissionMode: 'full-access', allowWrite: true, workspace: currentProject.path, aliases: ['codex'], enabled: true, supportsExecutionSelection: true },
      { id: 'cc4', displayName: 'Claude Code', type: 'claude-code', permissionMode: 'full-access', allowWrite: true, workspace: currentProject.path, aliases: ['claude'], enabled: true, supportsExecutionSelection: true },
      { id: 'qoder1', displayName: 'Qoder', type: 'qoder', permissionMode: 'full-access', allowWrite: true, workspace: currentProject.path, aliases: ['qoder'], enabled: true, supportsExecutionSelection: true },
      { id: 'hermes1', displayName: 'Hermes', type: 'hermes', permissionMode: 'full-access', allowWrite: true, workspace: currentProject.path, aliases: ['hermes'], enabled: true, supportsExecutionSelection: true },
    ] });
    return;
  }
  if (pathname === '/api/webapp/models' || /\/api\/webapp\/workers\/[^/]+\/models$/.test(pathname)) {
    await fulfillJson(route, {
      models: [
        { alias: 'codex-default', provider: 'codex', model: 'gpt-5.4', description: 'Codex 默认模型', source: 'static', isCurrent: true },
        { alias: 'claude-default', provider: 'claude-code', model: 'sonnet', description: 'Claude Code Sonnet', source: 'static' },
        { alias: 'qoder-default', provider: 'qoder', model: 'qoder-cli', description: 'Qoder CLI 默认模型', source: 'static' },
      ],
      reasoningEfforts: [
        { value: 'medium', label: 'Medium', description: '平衡速度与推理深度' },
        { value: 'high', label: 'High', description: '复杂任务深度推理' },
      ],
      source: 'static',
    });
    return;
  }
  if (pathname === '/api/webapp/worktrees') {
    await fulfillJson(route, { worktrees: [
      { id: 'main', name: 'master', path: currentProject.path, branch: 'master', head: '2c854b5', status: 'clean', isMain: true, isDetached: false, dirtyCount: 0, dirtyFiles: [], aheadMaster: 0, behindMaster: 0 },
      { id: 'qoder-review', name: 'qoder review', path: '/home/zhanxp/worktrees/tg-agent-gateway/qoder-review', branch: 'wt/qoder-review', head: 'b5b7ee2', status: 'clean', isMain: false, isDetached: false, dirtyCount: 0, dirtyFiles: [], aheadMaster: 1, behindMaster: 0 },
      { id: 'dirty-demo', name: 'dirty example', path: '/home/zhanxp/worktrees/tg-agent-gateway/dirty-demo', branch: 'wt/dirty-demo', head: '2c854b5', status: 'dirty · 2 files', isMain: false, isDetached: false, dirtyCount: 2, dirtyFiles: ['src/example.ts', 'TASK.md'], aheadMaster: 0, behindMaster: 0 },
    ] });
    return;
  }
  if (pathname === '/api/webapp/skills') {
    await fulfillJson(route, { skills: [
      { name: 'my-workflows', description: '协调计划、执行、Review 与集成', usageCount: 18 },
      { name: 'browser-qa', description: '浏览器 UI 自动验收', usageCount: 7 },
      { name: 'review', description: '独立代码审查', usageCount: 12 },
    ] });
    return;
  }
  if (pathname === '/api/webapp/tasks/auto' && request.method() === 'POST') {
    await fulfillJson(route, {
      success: true,
      workerName: 'qoder1',
      task: {
        id: 'task-ui-created',
        title: '生成移动端 UI 截图包',
        project: 'tg-agent-gateway',
        status: 'pending',
        routeType: 'execute',
        agent: 'qoder',
        resolvedAgent: 'qoder',
        recommendedAgent: 'qoder1',
        recommendedAgentLabel: 'Qoder',
        createdAt: now.toISOString(),
        worker: 'qoder1',
        worktreePath: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-created',
        executionWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-created',
        effectiveWorkspace: '/home/zhanxp/worktrees/tg-agent-gateway/tasks/qoder1-task-ui-created',
      },
    });
    return;
  }

  const taskMatch = pathname.match(/^\/api\/webapp\/tasks\/([^/]+)(?:\/(.*))?$/);
  if (taskMatch) {
    const taskId = decodeURIComponent(taskMatch[1]);
    const suffix = taskMatch[2] || '';
    const selectedTask = taskById.get(taskId) || reviewTask;
    if (suffix === 'events') {
      await fulfillJson(route, { taskId, events: taskId === reviewTask.id ? displayEvents : [] });
      return;
    }
    if (suffix === 'events/stream') {
      await route.fulfill({ status: 200, contentType: 'text/event-stream', body: 'event: done\ndata: {}\n\n' });
      return;
    }
    if (suffix === 'terminal-events') {
      await fulfillJson(route, { taskId, events: taskId === reviewTask.id ? terminalEvents : [], nextSeq: 3, taskStatus: selectedTask.status, timestamp: now.toISOString() });
      return;
    }
    if (suffix === 'agent-events') {
      await fulfillJson(route, { taskId, events: taskId === reviewTask.id ? agentEvents : [], nextSeq: 5, taskStatus: selectedTask.status, timestamp: now.toISOString() });
      return;
    }
    if (suffix === 'log') {
      await fulfillJson(route, { content: selectedTask.resultSummary || selectedTask.lastOutput || '', format: 'terminal', nextOffset: 0, size: 0, updatedAt: selectedTask.updatedAt, exists: true, taskStatus: selectedTask.status, timestamp: now.toISOString() });
      return;
    }
    if (suffix) {
      await fulfillJson(route, { success: true, message: 'UI inventory mock action', taskStatus: selectedTask.status });
      return;
    }
    await fulfillJson(route, selectedTask);
    return;
  }

  if (pathname === '/api/webapp/me') {
    await fulfillJson(route, { id: 1, firstName: 'UI Review', username: 'ui_inventory' });
    return;
  }

  unknownApiPaths.add(`${request.method()} ${pathname}`);
  await fulfillJson(route, {});
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const browser = await chromium.connectOverCDP(endpoint);
  const context = browser.contexts()[0];
  if (!context) throw new Error('Windows Chrome default context unavailable');

  const targetHost = new URL(targetUrl).host;
  for (const existingPage of context.pages()) {
    if (existingPage.url().includes(targetHost)) await existingPage.close();
  }
  const page = await context.newPage();
  const consoleErrors = new Set();
  const pageErrors = [];
  const unknownApiPaths = new Set();
  const captures = [];

  page.on('console', message => {
    if (message.type() === 'error') consoleErrors.add(message.text());
  });
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.route('https://telegram.org/js/telegram-web-app.js', route => route.fulfill({ status: 200, contentType: 'application/javascript', body: '' }));
  await page.route('**/api/**', route => handleApi(route, unknownApiPaths));
  await page.addInitScript(() => {
    const handlers = {};
    const noop = () => {};
    Object.defineProperty(window, 'Telegram', {
      configurable: true,
      value: {
        WebApp: {
          initData: 'query_id=ui-inventory&auth_date=1787718600&user=%7B%22id%22%3A1%7D&hash=ui-inventory',
          initDataUnsafe: { user: { id: 1, first_name: 'UI Review', username: 'ui_inventory' } },
          themeParams: {},
          colorScheme: 'light',
          isExpanded: true,
          viewportHeight: window.innerHeight,
          viewportStableHeight: window.innerHeight,
          ready: noop,
          expand: noop,
          setHeaderColor: noop,
          setBackgroundColor: noop,
          enableClosingConfirmation: noop,
          disableClosingConfirmation: noop,
          onEvent: (name, callback) => { handlers[name] = handlers[name] || []; handlers[name].push(callback); },
          offEvent: (name, callback) => { handlers[name] = (handlers[name] || []).filter(item => item !== callback); },
          showAlert: noop,
          showConfirm: (_message, callback) => callback(true),
          showPopup: (_params, callback) => callback && callback('ok'),
          HapticFeedback: { impactOccurred: noop, notificationOccurred: noop, selectionChanged: noop },
          MainButton: { text: '', color: '', textColor: '', isVisible: false, isActive: true, isProgressVisible: false, setText: noop, onClick: noop, offClick: noop, show: noop, hide: noop, enable: noop, disable: noop, showProgress: noop, hideProgress: noop, setParams: noop },
          BackButton: { isVisible: false, onClick: noop, offClick: noop, show: noop, hide: noop },
        },
      },
    });
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' });

  async function capture(fileName, state, proofText) {
    if (proofText) {
      await page.waitForFunction(text => Array.from(document.querySelectorAll('body *')).some(element => {
        if ((element.textContent || '').trim() !== text) return false;
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
      }), proofText, { timeout: 10_000 });
    }
    await page.waitForTimeout(350);
    await page.evaluate(() => {
      for (const selector of [
        '#immersive-translate-popup',
        '#immersive-translate-input-popup',
        '#immersive-translate-browser-popup',
      ]) {
        for (const element of document.querySelectorAll(selector)) {
          element.setAttribute('style', 'display: none !important');
        }
      }
    });
    const target = path.join(outputDir, fileName);
    await page.screenshot({ path: target, fullPage: false, animations: 'disabled' });
    const size = fs.statSync(target).size;
    captures.push({ file: fileName, state, size, viewport: { width: 390, height: 844 } });
  }

  function tab(label) {
    return page.locator('.app-tabbar button').filter({ hasText: label });
  }

  await page.goto(`${targetUrl}?source=ui-inventory#ui-inventory`, { waitUntil: 'domcontentloaded', timeout: 20_000 });
  await page.locator('.app-tabbar').waitFor({ state: 'visible', timeout: 15_000 });
  await capture('01-home-dashboard.png', '首页 / Dashboard', '运行中任务');

  await page.getByRole('button', { name: '打开项目侧边栏' }).click();
  await capture('02-project-sidebar.png', '项目侧栏 / Project switcher', '计划文档');
  await page.getByRole('button', { name: '关闭项目侧边栏' }).last().click();

  await tab('任务').click();
  await capture('03-tasks-list.png', '任务列表 / Tasks', '任务列表');

  await page.locator('button:visible').filter({ hasText: '待验收' }).first().click();
  await capture('04-tasks-pending-review.png', '任务列表 / 待验收筛选', reviewTask.title);

  await page.locator('h3:visible').filter({ hasText: reviewTask.title }).first().click();
  await capture('05-task-detail.png', '任务详情 Sheet', '任务详情');
  await page.getByRole('button', { name: '返回' }).click();

  await tab('执行').click();
  await capture('06-new-task.png', '创建新任务 / Execute', '创建新任务');

  await page.getByRole('button', { name: '设置执行方式和模型' }).click();
  await page.getByRole('dialog', { name: '执行配置' }).waitFor({ state: 'visible' });
  await capture('07-execution-config.png', 'Execution Agent / Model / Worktree 配置', 'Execution Agent');
  await page.getByRole('button', { name: '关闭执行配置菜单' }).evaluate(element => element.click());

  await page.getByRole('button', { name: '添加附件' }).click();
  await capture('08-attachment-menu.png', '附件菜单 / 图片与文件', '上传图片');
  await page.getByRole('button', { name: '添加附件' }).click();

  const promptInput = page.getByPlaceholder('描述你想让 AI 完成的任务...');
  await promptInput.fill('/');
  await capture('09-slash-command-menu.png', 'Slash command 建议菜单', '/commit');

  await promptInput.fill('生成当前 WebApp 的移动端 UI 页面清单和截图包');
  await page.getByRole('button', { name: '提交任务' }).click();
  const successHeading = page.getByRole('heading', { name: '任务已创建' });
  await successHeading.waitFor({ state: 'visible', timeout: 10_000 });
  await successHeading.scrollIntoViewIfNeeded();
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    document.querySelector('main')?.scrollTo(0, 0);
  });
  await capture('10-task-created.png', '任务创建成功态', '任务已创建');

  await tab('队列').click();
  await capture('11-queue.png', '队列 / Pending tasks', queuedTask.title);

  await tab('消息').click();
  await capture('12-messages.png', '消息 / Review inbox', '消息');

  const report = {
    generatedAt: new Date().toISOString(),
    sourceCommit,
    targetUrl,
    browser: 'Windows Chrome via CDP 9222 relay',
    viewport: { width: 390, height: 844 },
    captures,
    unknownApiPaths: Array.from(unknownApiPaths).sort(),
    consoleErrors: Array.from(consoleErrors),
    pageErrors,
  };
  fs.writeFileSync(path.join(outputDir, 'capture-report.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report, null, 2));
  await page.close();
  process.exit(0);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
