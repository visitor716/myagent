#!/usr/bin/env python3
"""
生成中文版本的skill总览HTML
"""
import os
import re
import html
from datetime import datetime
from pathlib import Path

SKILLS_DIR = Path(__file__).parent.parent / "skills"
OUTPUT_HTML = SKILLS_DIR / "skill-trigger-overview.html"

# 技能描述的中文翻译映射
SKILL_TRANSLATIONS = {
    "agent-usage-monitor": {
        "desc": "监控多个 Agent 的使用量，定期截图并发送通知",
        "triggers": ["监控多个 Agent 的使用量", "定期截图并发送通知", "agent usage monitor"]
    },
    "ai-slop-cleaner": {
        "desc": "[OMX] 运行反冗余清理/重构/去噪工作流",
        "triggers": ["[OMX] 运行反冗余清理/重构/去噪工作流", "ai slop cleaner"]
    },
    "analyze": {
        "desc": "[OMX] 运行只读深度仓库分析并返回带有明确置信度、具体文件引用和清晰证据-推理边界的排序综合结果。当用户说“analyze”、“investigate”、“why does”、“what's causing”或在提出任何更改之前需要有根据的跨文件解释时使用。",
        "triggers": ["analyze", "investigate", "why does", "what's causing", "需要有根据的跨文件解释"]
    },
    "audio": {
        "desc": "从 audio.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问音频相关工作流帮助时使用。",
        "triggers": ["audio", "音频相关工作流"]
    },
    "cc-connect-bot-setup": {
        "desc": "配置和诊断 cc-connect Telegram 机器人桥接和 Claude Code 权限默认值，特别是每个机器人的 Claude Code/Codex 模式、全局 Claude Code 启动 bypassPermissions、全自动默认值、WSL/systemd 启动回退、配置备份和安全重启。当用户提到 cc-connect、Telegram 机器人桥接权限、Claude/Cloud Code 权限边界、bypassPermissions、全自动/建议/计划/YOLO 模式或重启 cc-connect 时使用。",
        "triggers": ["cc-connect", "Telegram 机器人桥接", "配置权限", "重启 cc-connect"]
    },
    "cc-switch-skill": {
        "desc": "从 WSL 或 Windows 支持的主目录诊断和操作 cc-switch。当用户提到 cc-switch、providers、models、apis、provider-count 不匹配、Windows GUI 数据库初始化失败（如“database is locked”）、想要列出/切换/添加/编辑/验证 cc-switch 提供程序，或说诸如“切换到百度 CC”/“百度 CC”之类的短语将 bdcc1 Claude Code 切换到百度千帆时使用。",
        "triggers": ["cc-switch", "切换模型", "database is locked", "百度 CC"]
    },
    "clash-proxy": {
        "desc": "从 WSL 安全诊断和配置 Windows 和 WSL 代理网络。当用户提到 Windows proxy、WSL proxy、Clash、Clash Verge、Mihomo、sing-box、V2Ray、system proxy、WinHTTP、TUN、DNS 劫持、aTrust、深信服/Sangfor VPN、公司内网拆分路由、企业微信内网访问、Clash/aTrust 冲突、http_proxy/https_proxy/all_proxy、tmux 代理继承、代理区域策略（如 US-first Japan-fallback no-Hong-Kong），或询问 Windows/WSL 网络代理/代理软件/代理环境时使用。",
        "triggers": ["Clash", "代理", "网络代理", "Windows proxy", "WSL proxy"]
    },
    "code-review": {
        "desc": "[OMX] 运行全面的代码审查",
        "triggers": ["code review", "代码审查"]
    },
    "codex-plan-claude-exec-review": {
        "desc": "当用户希望 Codex 创建或改进计划、将计划交给 Claude Code worker 在隔离工作树中实现、选择或安排 tg-agent-gateway cc worker、然后让 Codex 对已完成的 Claude 工作进行只读审查、集成接受的更改、验证以及在需要时刷新本地网关运行时时使用。触发包括“安排 cc”、“安排cc”、“把计划交给 Claude 做”、“Claude 做完你 review”、“Codex 规划 Claude 执行 Codex 检查”、“plan to claude execute to codex review”以及类似的交接/审查工作流。",
        "triggers": ["安排 cc", "把计划交给 Claude 做", "Claude 做完你 review", "Codex 规划 Claude 执行"]
    },
    "codex-task-queue": {
        "desc": "为已运行的 Codex 终端或 tmux 会话排队后续需求，然后等待明确的完成标记，发送 /compact，并注入下一个排队任务。当用户希望当前任务完成、压缩和排队任务继续、要求向 Codex 队列添加需求，或想要持久的本地 Codex 任务积压时使用。",
        "triggers": ["任务队列", "/compact", "排队任务"]
    },
    "coding-standards": {
        "desc": "用于命名、可读性、不可变性和代码质量审查的基线跨项目编码约定。使用详细的前端或后端技能来获取框架特定模式。",
        "triggers": ["编码标准", "coding standards", "代码约定"]
    },
    "commit": {
        "desc": "从 commit.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问提交相关工作流帮助时使用。",
        "triggers": ["commit", "提交"]
    },
    "create-telegram-bot-bridge": {
        "desc": "当用户希望为 Claude-to-IM 创建新的 Telegram 机器人、轮换 Telegram 机器人令牌、将桥接重新绑定到新的 Telegram 机器人，或清理错误创建的 BotFather 机器人时使用。此技能驱动 BotFather 或 Telegram Web，解析私有 chat_id，更新 ~/.claude-to-im/config.env，可选地重启桥接，验证新机器人，并仅通过受保护的脚本安全删除错误创建的机器人。",
        "triggers": ["创建 Telegram 机器人", "Telegram bot", "BotFather"]
    },
    "daily-report-table": {
        "desc": "将粘贴的 TCP 日报文本转换为固定表格行，用于主日报和可选的光斑调试表。当用户提供中文日报/调试记录、想要固定的企业微信或 Markdown 表格输出，或需要将光斑、能量偏移、设备异常注释转换为结构化行时使用。",
        "triggers": ["日报", "光斑调试表", "TCP 日报"]
    },
    "deploy": {
        "desc": "从 deploy.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问部署相关工作流帮助时使用。",
        "triggers": ["deploy", "部署"]
    },
    "deploy-to-vercel": {
        "desc": "将应用和网站部署到 Vercel。当用户要求部署操作如“deploy my app”、“deploy and give me the link”、“push this live”或“create a preview deployment”时使用。",
        "triggers": ["deploy my app", "部署到 Vercel", "Vercel 部署"]
    },
    "disable-mcp-startup": {
        "desc": "在不进行广泛配置重写的情况下，禁用 Codex 和 Claude Code 的损坏或不需要的 MCP 启动条目。当用户要求禁用 MCP、不启动 MCP 工具、移除 MCP 启动警告、静默 chrome-devtools 或 context7 启动失败、避免浏览器 MCP、清理 MCP 允许列表、修复 Codex 更新后重新出现的 MCP 条目，或确保运行时和 myagent 配置模板在恢复时不会重新启用 MCP 时使用。",
        "triggers": ["禁用 MCP", "不启动 MCP", "MCP 启动"]
    },
    "find-docs": {
        "desc": "查找文档",
        "triggers": ["find docs", "查找文档"]
    },
    "find-skills": {
        "desc": "帮助用户发现和安装 Agent 技能，当用户问“how do I do X”、“find a skill for X”、“is there a skill that can…”或表达扩展能力的兴趣时使用。当用户寻找可能作为可安装技能存在的功能时应使用此技能。",
        "triggers": ["find skill", "查找技能", "发现技能"]
    },
    "lint": {
        "desc": "从 lint.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问 lint 相关工作流帮助时使用。",
        "triggers": ["lint", "代码检查"]
    },
    "merge-worktree-master": {
        "desc": "安全地将 tg-agent-gateway worker 工作树合并到本地 master，验证，重启 Gateway/WebApp，将最新的 /app 发布发送到 Telegram 机器人进行电话自测，然后可选地推送/同步/清理 worker 引用。当用户要求合并就绪工作树、批量合并 worker 分支、完成接受的 cc/cx 补丁、在电话上自测最新的 master、接受后推送 worker 引用、检查/分类脏工作树、清理过时 worker 会话，或询问活动 worker 分支是否是最新时使用。",
        "triggers": ["合并工作树", "merge worktree", "/app"]
    },
    "neocd-change-workflow": {
        "desc": "在 NeoCD/offMusicPlayer 仓库中实现和验证代码更改。当 Codex 需要添加功能、修复 bug、重构页面/组件/hooks/服务、更新测试，或在遵循项目特定规则（如 IndexedDB 优先本地存储、Tailwind 样式、中文代码注释、/tests 下的测试、无破坏性删除以及强制的 `npx tsc --noEmit` 清理循环）时进行其他仓库本地代码更改时使用。",
        "triggers": ["neocd", "offMusicPlayer", "npx tsc --noEmit"]
    },
    "oa-exception-record-filler": {
        "desc": "从 TCP 日报文本填充并保存 DR Laser OA 新建异常记录表单。当用户要求将日报内容添加到 OA 异常记录表、新建异常记录、5.xx 异常记录，或说保存 OA 异常记录而不提交时使用。",
        "triggers": ["OA 异常记录", "新建异常记录", "日报内容"]
    },
    "opencli-adapter-author": {
        "desc": "在为新站点编写 OpenCLI 适配器或向现有站点添加新命令时使用。端到端指导从首次侦察到字段解码、适配器编码和验证。替代 opencli-oneshot / opencli-explorer。对于临时浏览器驱动（无适配器），请参阅 opencli-browser；有关 OpenCLI 的顶级介绍，请参阅 opencli-usage。",
        "triggers": ["opencli adapter", "OpenCLI 适配器"]
    },
    "opencli-autofix": {
        "desc": "命令失败时自动修复损坏的 OpenCLI 适配器。当 opencli 命令失败时加载此技能——它指导你收集跟踪工件、修补适配器、重试，并在验证修复后提交上游 GitHub 问题。适用于任何 AI Agent。",
        "triggers": ["opencli autofix", "修复 OpenCLI"]
    },
    "opencli-browser": {
        "desc": "当 Agent 需要通过 opencli 驱动真实的 Chrome 窗口时使用——检查页面、填写表单、点击登录流程，或临时提取数据。涵盖选择器优先目标契约、复合表单字段、过时引用处理、网络捕获以及 CLI 返回的 Agent 原生信封。不适用于编写适配器——请参阅 opencli-adapter-author。",
        "triggers": ["opencli browser", "浏览器驱动"]
    },
    "opencli-usage": {
        "desc": "在任何 OpenCLI 会话开始时使用——这是 `opencli` 可以做什么、如何发现适配器、哪些标志和输出格式是通用的，以及接下来加载哪个专门技能的顶级地图。当 Agent 问“what can opencli do?”或“how do I find the right command?”时指向这里。",
        "triggers": ["opencli usage", "OpenCLI 使用"]
    },
    "personal-balance-sheet": {
        "desc": "当从帐户截图更新个人资产负债表 Excel 工作簿、将同月应收账款/负债汇总工作簿合并回资产工作簿、按日期文件夹组织资产负债表文件、将主资产负债表拆分为流动资产、投资资产、应收账款和负债等类别工作表、导出应收款/贷款明细工作簿、将万元工作簿转换为实际人民币金额、组织明细截图文件夹、按可见金额重命名截图，或验证中文个人资产/负债工作簿时使用。处理 WSL/Windows 路径、截图派生金额、单位转换以及对缺失财务数据的保守处理。",
        "triggers": ["资产负债表", "个人理财", "balance sheet"]
    },
    "personal-bookkeeping": {
        "desc": "分析来自支付宝、微信支付或银行 CSV 文件的个人交易导出。当用户要求记账、账单分析、每月花费、支付宝/微信/银行卡交易明细统计、消费分类、支出汇总，或想要从个人支出中移除可报销的工作支出（如出差酒店房费）时使用。",
        "triggers": ["记账", "账单分析", "支付宝", "微信支付"]
    },
    "pr": {
        "desc": "从 pr.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问 PR 相关工作流帮助时使用。",
        "triggers": ["pr", "pull request", "拉取请求"]
    },
    "reimbursement-screenshot-organizer": {
        "desc": "通过读取文件内容、提取日期、商家、金额、文档类型、证据类型、发票字段和置信度，然后安全重命名、分类、检查合规性、简化/编号火车票、滴滴行程单和比价图文件名、裁剪/合并行程单 PDF 到 Word 文档、将比价图图像合并到单个 Word 网格、生成可复制的 OA 差旅/明细发票表格，以及可选地浏览器填写 OA 字段而不保存/提交，来组织和审计报销/费用截图、PDF 和下载的电子邮件附件。当用户提到报销、费用报销、报销规范核对、发票截图、支付凭证、票据整理、滴滴发票、火车票命名、铁路电子客票、行程单、行程单命名、行程单合并、行程单转 Word、比价图、比价图命名、比价图合并、邮箱发票、OA 复制填写、OA 自动填、差旅报销模块、发票号码填写、receipt screenshots、PDF invoices、expense evidence，或要求 Codex 重命名/分类/检查/下载/裁剪/合并报销目录中的文件时使用。",
        "triggers": ["报销", "费用报销", "发票截图", "滴滴发票", "火车票"]
    },
    "review": {
        "desc": "从 review.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问审查相关工作流帮助时使用。",
        "triggers": ["review", "审查"]
    },
    "security-review": {
        "desc": "在添加身份验证、处理用户输入、处理机密、创建 API 端点或实现支付/敏感功能时使用此技能。提供全面的安全检查表和模式。",
        "triggers": ["安全审查", "security review", "安全检查"]
    },
    "sqlite-admin": {
        "desc": "SQLite 数据库管理工具集，用于安全检查、查询和备份 TG Agent Gateway 的任务数据库",
        "triggers": ["sqlite admin", "SQLite 管理", "数据库管理"]
    },
    "sync-shared-skills": {
        "desc": "在 Codex、Claude Code、Hermes 和 myagent 真实源仓库之间同步通用用户技能和可重用的 AI 运行时配置。当用户说“同步skill”、“同步技能”、“sync skill”、“sync skills”、“同步配置”、“备份配置”、“备份 Codex 配置”，或要求将技能/配置/运行时 Agent 体验镜像到 myagent 时使用。从选定的源端同步到目标端，同时跳过仅运行时、系统、未管理的冲突和敏感运行时状态。",
        "triggers": ["同步 skill", "同步技能", "备份配置", "sync skills"]
    },
    "telegram-input-flow": {
        "desc": "实现移动友好的 Telegram 机器人多步骤文本和任务执行工作流。当 Codex 需要将按钮驱动的 Telegram 交互转换为“点击按钮、提示文本、下一条消息创建/更新实体”工作流时，或在添加等待输入会话状态、/cancel 处理、callback_query 清理、Running 卡片、异步任务完成/失败报告、成功操作按钮以及 Telegraf/Telegram 机器人 UX 测试时使用。",
        "triggers": ["Telegram 输入流", "/cancel", "Telegram bot"]
    },
    "test": {
        "desc": "从 test.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问测试相关工作流帮助时使用。",
        "triggers": ["test", "测试"]
    },
    "tg-agent-gateway-worktree-acceptance": {
        "desc": "通过检查 data/bots.json useWorktree 设置、git 工作树清单、runner cwd/effectiveWorkspace 链和最近日志，验证 tg-agent-gateway worker 是否真正在 Git 工作树中执行。当被要求验证 tg-agent-gateway 工作树隔离、worker cwd、effectiveWorkspace/worktreePath、并行 worker 隔离或工作树验收时使用。",
        "triggers": ["工作树验收", "worktree acceptance", "tg-agent-gateway"]
    },
    "tg-app-release-command": {
        "desc": "实现、验证或操作 tg-agent-gateway /app、/webapp 和 /latest_app 命令，以便它们向 Telegram 机器人发送最新的 WebApp 条目，包含发布版本、分支名称、commit、部署时间、最新更新说明和新的 WebApp 按钮。当用户要求让 /app 发送最新应用、包含版本/分支/部署时间/更新内容、让版本跨分支更改，或诊断过时的 WebApp 发布信息时使用。",
        "triggers": ["/app", "/webapp", "/latest_app", "应用发布"]
    },
    "tg-gateway-menu-recovery": {
        "desc": "诊断和修复 tg-agent-gateway Telegram 菜单、命令栏或移动 WebApp 无响应事件，包括 /menu 不返回、Telegram 底部菜单点击无效、手机 WebApp 空白/无 UI、指向旧 Cloudflare 快速隧道的过时 Telegram WebApp 弹窗、仍在运行但报告 Unauthorized/Tunnel not found 的 Cloudflare 快速隧道进程、发送最新 App/WebApp 条目到机器人的请求、WebApp URL 或隧道目标漂移、网关重启但机器人不活跃、通过重建/重启加上缓存破坏新按钮修复的手机 WebApp 加载循环、Telegraf 启动/轮询挂起、失去代理环境的 tmux 重启脚本、setMyCommands/setChatMenuButton 失败、callback_data 漂移（如 back_to_main vs back_to_menu）以及 launchAsBot worker 令牌轮询冲突。当在 /home/zhanxp/projects/tg-agent-gateway 中处理 Telegram Bot UI、WebApp 条目、管理器机器人启动、重启脚本或移动菜单恢复时使用。",
        "triggers": ["Telegram 菜单恢复", "/menu", "tg-gateway"]
    },
    "typecheck": {
        "desc": "从 typecheck.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问类型检查相关工作流帮助时使用。",
        "triggers": ["typecheck", "类型检查"]
    },
    "ultraqa": {
        "desc": "[OMX] QA 循环工作流——测试、验证、修复、重复直到达到目标",
        "triggers": ["ultraqa", "QA 循环", "测试验证修复"]
    },
    "vercel": {
        "desc": "从 vercel.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问 Vercel 相关工作流帮助时使用。",
        "triggers": ["vercel", "Vercel"]
    },
    "vercel-composition-patterns": {
        "desc": "Vercel 组合模式",
        "triggers": ["vercel composition patterns", "Vercel 组合模式"]
    },
    "vercel-react-best-practices": {
        "desc": "来自 Vercel 工程团队的 React 和 Next.js 性能优化指南。在编写、审查或重构 React/Next.js 代码以确保最佳性能模式时应使用此技能。触发于涉及 React 组件、Next.js 页面、数据获取、包优化或性能改进的任务。",
        "triggers": ["React 最佳实践", "Next.js 优化", "Vercel 性能"]
    },
    "vercel-react-native-skills": {
        "desc": "Vercel React Native 技能",
        "triggers": ["vercel react native skills", "React Native"]
    },
    "vitest": {
        "desc": "从 vitest.md 导入的 Claude Code 扁平技能。当任务匹配下面描述的工作流或用户询问 vitest 相关工作流帮助时使用。",
        "triggers": ["vitest", "测试"]
    },
    "web-design-guidelines": {
        "desc": "审查 UI 代码的 Web 界面指南合规性。当被要求“review my UI”、“check accessibility”、“audit design”、“review UX”或“check my site against best practices”时使用。",
        "triggers": ["review my UI", "检查可访问性", "设计审计", "UX 审查"]
    },
    "windows-document-organizer": {
        "desc": "使用试运行清单、精确重复检测、内容辅助分类、已审查的移动计划、可跟踪索引和非破坏性文件移动，从 WSL 安全组织 Windows 挂载的文档文件夹。当用户要求整理资料、整理目录、分类 D:\\ 或 /mnt 驱动器工作文件夹、去重文档、保留现有精选子树、生成 00_资料索引日志，或在不删除原件的情况下清理混合 Office/PDF/图像/项目文件时使用。",
        "triggers": ["整理资料", "整理目录", "文档整理", "/mnt"]
    },
    "windows-system-settings": {
        "desc": "使用内置 Windows 工具从 WSL/Codex 安全检查和调整 Windows 系统设置。当用户要求更改 Windows 亮度、修复灰色/禁用的亮度滑块、检查监视器/显示状态、更改音量、静音状态、显示超时、睡眠超时、电源计划、时区、监视器/显示行为，或说系统设置、Windows 设置、调亮度、亮度灰色、亮度滑块灰色、降低亮度、调音量、静音、电源设置、睡眠时间、屏幕关闭时间或类似的本地机器设置请求时使用。",
        "triggers": ["Windows 设置", "调亮度", "亮度灰色", "系统设置"]
    },
    "worktree-execution-acceptance": {
        "desc": "在验证 Git 工作树隔离是否真正连接到 Agent 或 runner 任务执行流时使用。专注于证明真实进程 cwd/pwd 是 worker 工作树，而不仅仅是工作树存在。检查工作树列表、worker 配置、数据库任务记录、runner cwd 解析、日志，以及在不修改业务代码的情况下可选的临时文件隔离探针。",
        "triggers": ["工作树执行验收", "worktree execution", "Git 工作树"]
    },
    "wsl-windows-chrome": {
        "desc": "从 WSL 连接到专用 Windows Chrome Agent 浏览器，位于 C:\\chrome-wsl-automation，固定 CDP 端口 9222，配置文件 Default。每当 Agent 需要浏览器自动化、保留登录状态、Windows Chrome CDP、已验证页面或已登录企业网站时，首先使用此技能；永远不要使用临时/无痕/访客配置文件或清除 Cookie/存储。",
        "triggers": ["Windows Chrome", "浏览器自动化", "CDP 端口 9222"]
    },
    "wsl-windows-path-compat": {
        "desc": "当在 WSL/Linux 中运行的 Agent 无法读取 Windows 文件路径、截图、图像、Telegram 附件或文件 URL（如 C:\\Users\\...\\image.png 或 file:///C:/...）时使用。将 Windows 路径转换为 /mnt/<drive>/ 路径，添加 runner 提示，并验证转换后的路径到达 Claude Code、Codex、Hermes 或 tg-agent-gateway worker。",
        "triggers": ["Windows 路径", "/mnt", "路径转换"]
    },
    "wx-cli": {
        "desc": "wx-cli — 从本地微信数据库查询聊天记录、联系人、会话、收藏等。用户提到微信聊天记录、联系人、消息历史、群成员、收藏内容时，使用此 skill 安装并调用 wx-cli。",
        "triggers": ["微信聊天记录", "wx-cli", "微信数据库"]
    },
}


def read_skill_md(skill_path: Path) -> dict:
    """读取 SKILL.md 文件并提取信息"""
    skill_file = skill_path / "SKILL.md"
    if not skill_file.exists():
        return None

    content = skill_file.read_text(encoding="utf-8")

    # 提取 frontmatter
    frontmatter = {}
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            fm_content = parts[1]
            for line in fm_content.strip().split("\n"):
                line = line.strip()
                if ":" in line:
                    key, value = line.split(":", 1)
                    frontmatter[key.strip()] = value.strip()

    # 获取 skill 名称
    skill_name = skill_path.name

    # 使用翻译或原始内容
    translation = SKILL_TRANSLATIONS.get(skill_name, {})
    desc = translation.get("desc", frontmatter.get("description", ""))
    if not desc:
        # 从内容中提取描述
        desc = content[:200] if content else "无 description 元数据。"

    # 确定来源组
    group = "unknown"
    if "skills-download" in str(skill_path):
        group = "skills-download"
    elif "skills-local" in str(skill_path):
        group = "skills-local"

    return {
        "name": skill_name,
        "desc": desc,
        "group": group,
        "path": skill_path,
        "frontmatter": frontmatter,
        "translation": translation,
    }


def find_skills():
    """查找所有 skills"""
    skills = {}
    skills_local = SKILLS_DIR / "skills-local"
    skills_download = SKILLS_DIR / "skills-download"

    # 扫描 skills-local
    for skill_dir in sorted(skills_local.iterdir()):
        if skill_dir.is_dir():
            skill = read_skill_md(skill_dir)
            if skill:
                if skill["name"] not in skills:
                    skills[skill["name"]] = {
                        "info": skill,
                        "paths": [],
                    }
                skills[skill["name"]]["paths"].append(("skills-local", skill_dir))

    # 扫描 skills-download
    for skill_dir in sorted(skills_download.iterdir()):
        if skill_dir.is_dir():
            skill = read_skill_md(skill_dir)
            if skill:
                if skill["name"] not in skills:
                    skills[skill["name"]] = {
                        "info": skill,
                        "paths": [],
                    }
                skills[skill["name"]]["paths"].append(("skills-download", skill_dir))

    return skills



def build_html(skills):
    """构建 HTML"""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S %Z")

    # 统计
    total_skills = len(skills)
    has_local = 0
    has_download = 0
    symlink_count = 0

    cards = []

    for skill_name, skill_data in sorted(skills.items()):
        info = skill_data["info"]
        paths = skill_data["paths"]

        # 确定显示的组
        groups = set(p[0] for p in paths)
        if len(groups) > 1:
            display_group = "mixed"
            path_label = "本地/链接 / 下载/管理"
        elif "skills-local" in groups:
            display_group = "skills-local"
            path_label = "本地/链接"
        else:
            display_group = "skills-download"
            path_label = "下载/管理"

        # 统计
        if any(p[0] == "skills-local" for p in paths):
            has_local += 1
        if any(p[0] == "skills-download" for p in paths):
            has_download += 1

        # 获取翻译的触发词
        translation = info.get("translation", {})
        trigger_chips = translation.get("triggers", [])
        if not trigger_chips:
            # 回退到从 frontmatter 或描述中提取
            trigger_chips = [info["desc"][:50]]

        # 构建搜索文本
        search_text = f"{skill_name} {info['desc']} {' '.join(trigger_chips)}".lower()

        # 构建路径列表 HTML
        path_items = []
        for group_name, path in paths:
            # 构建显示路径
            display_path = f"{group_name}/{path.name}"
            if path.is_symlink():
                try:
                    target = path.readlink()
                    target_str = str(target)
                    # 如果目标指向项目内的路径，简化显示
                    if "/myagent/skills/skills-download/" in target_str:
                        target_display = "skills-download/" + path.name
                    elif "/myagent/skills/skills-local/" in target_str:
                        target_display = "skills-local/" + path.name
                    else:
                        target_display = target_str
                    display_path = f"{display_path} -> {target_display}"
                except:
                    pass
            path_items.append(f"<li><code>{html.escape(display_path)}</code></li>")

        # 检查是否有 agent 默认提示
        agent_prompt = ""
        agent_yaml = info["path"] / "agents" / "openai.yaml"
        if agent_yaml.exists():
            try:
                yaml_content = agent_yaml.read_text(encoding="utf-8")
                # 简单提取一些内容
                if yaml_content:
                    agent_prompt = yaml_content[:300]
            except:
                pass

        # 构建卡片
        card = f'''
      <article class="skill-card" data-group="{html.escape(display_group)}" data-text="{html.escape(search_text)}">
        <div class="card-head">
          <div>
            <h2>{html.escape(skill_name)}</h2>
            <p class="path">{html.escape(path_label)}</p>
          </div>
          <span class="badge">{len(paths)} 路径</span>
        </div>
        <p class="desc">{html.escape(info["desc"])}</p>
        <div class="trigger-block">
          <h3>自然语言触发词</h3>
          <div class="chips">{"".join(f'<span class="chip">{html.escape(t)}</span>' for t in trigger_chips[:12])}</div>
        </div>
        <div class="meta">
          {"".join(f'<div class="meta-row"><span>{html.escape(k)}</span><code>{html.escape(v)}</code></div>' for k, v in info["frontmatter"].items() if k in ["argument-hint", "args-hint"] and v)}
          {f'<div class="meta-row"><span>来源记录</span><span>github</span></div>' if display_group == "skills-download" else ""}
        </div>
        <details class="paths"><summary>来源路径</summary><ul>{"".join(path_items)}</ul></details>
        {f'<details><summary>Agent 默认提示</summary><p>{html.escape(agent_prompt)}</p></details>' if agent_prompt else ""}
      </article>
'''
        cards.append(card)

    html_template = f'''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MyAgent Skill 触发词总览</title>
  <style>
    :root {{
      --bg: #f6f4ee;
      --ink: #1f2a24;
      --muted: #66736b;
      --line: #d9d2c3;
      --panel: #fffdf8;
      --accent: #196f63;
      --accent-2: #b83f2b;
      --accent-3: #305f9c;
      --chip: #e8f2ef;
      --shadow: 0 14px 34px rgba(38, 52, 43, .08);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background:
        linear-gradient(135deg, rgba(25,111,99,.10), transparent 32%),
        linear-gradient(315deg, rgba(184,63,43,.08), transparent 28%),
        var(--bg);
      color: var(--ink);
      font-family: ui-sans-serif, "Segoe UI", "Noto Sans SC", "Microsoft YaHei", sans-serif;
      line-height: 1.55;
    }}
    .shell {{ width: min(1180px, calc(100% - 32px)); margin: 0 auto; }}
    header {{ padding: 48px 0 22px; }}
    .eyebrow {{ margin: 0 0 8px; color: var(--accent); font-weight: 700; letter-spacing: 0; }}
    h1 {{ margin: 0; font-size: clamp(30px, 5vw, 58px); line-height: 1.05; letter-spacing: 0; }}
    .lead {{ max-width: 860px; margin: 16px 0 0; color: var(--muted); font-size: 17px; }}
    .stats {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 24px 0 0; }}
    .stat {{ padding: 10px 14px; border: 1px solid var(--line); background: rgba(255,253,248,.72); border-radius: 8px; }}
    .stat strong {{ display: block; font-size: 22px; line-height: 1.1; }}
    .stat span {{ color: var(--muted); font-size: 13px; }}
    .toolbar {{
      position: sticky;
      top: 0;
      z-index: 10;
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 12px;
      align-items: center;
      padding: 14px 0;
      backdrop-filter: blur(12px);
      background: rgba(246,244,238,.86);
      border-bottom: 1px solid rgba(217,210,195,.78);
    }}
    .search {{ width: 100%; min-height: 44px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); color: var(--ink); padding: 0 14px; font-size: 15px; outline: none; }}
    .search:focus {{ border-color: var(--accent); box-shadow: 0 0 0 3px rgba(25,111,99,.14); }}
    .filters {{ display: inline-flex; gap: 6px; padding: 4px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }}
    .filters button {{ min-height: 36px; border: 0; border-radius: 6px; padding: 0 12px; background: transparent; color: var(--muted); cursor: pointer; font-weight: 650; white-space: nowrap; }}
    .filters button.active {{ background: var(--accent); color: white; }}
    main {{ padding: 22px 0 56px; }}
    .grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }}
    .skill-card {{ background: var(--panel); border: 1px solid var(--line); border-radius: 8px; box-shadow: var(--shadow); padding: 18px; min-width: 0; }}
    .card-head {{ display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; }}
    h2 {{ margin: 0; font-size: 22px; letter-spacing: 0; overflow-wrap: anywhere; }}
    .path {{ margin: 4px 0 0; color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }}
    .badge {{ flex: 0 0 auto; border-radius: 999px; padding: 5px 9px; background: #f0e7d8; color: #6b4b21; font-size: 12px; font-weight: 700; }}
    .desc {{ margin: 14px 0; color: #35413a; }}
    .trigger-block h3 {{ margin: 0 0 8px; font-size: 14px; color: var(--accent-3); letter-spacing: 0; }}
    .chips {{ display: flex; flex-wrap: wrap; gap: 7px; }}
    .chip {{ display: inline-flex; align-items: center; max-width: 100%; min-height: 28px; padding: 4px 9px; border-radius: 999px; background: var(--chip); color: #164b43; border: 1px solid #cae0da; font-size: 13px; overflow-wrap: anywhere; }}
    .meta {{ margin-top: 14px; display: grid; gap: 8px; }}
    .meta-row {{ display: grid; grid-template-columns: 72px minmax(0, 1fr); gap: 8px; color: var(--muted); font-size: 13px; }}
    code {{ background: #f0eee6; color: #26342b; padding: 2px 5px; border-radius: 5px; overflow-wrap: anywhere; }}
    details {{ margin-top: 14px; border-top: 1px solid var(--line); padding-top: 10px; color: var(--muted); }}
    summary {{ cursor: pointer; font-weight: 700; color: var(--accent-2); }}
    details p {{ margin: 8px 0 0; }}
    .paths ul {{ margin: 8px 0 0; padding-left: 18px; }}
    .paths li {{ margin: 5px 0; overflow-wrap: anywhere; }}
    .empty {{ display: none; padding: 32px; text-align: center; color: var(--muted); border: 1px dashed var(--line); border-radius: 8px; background: rgba(255,253,248,.7); }}
    footer {{ padding: 0 0 44px; color: var(--muted); font-size: 13px; }}
    @media (max-width: 760px) {{
      .shell {{ width: min(100% - 24px, 1180px); }}
      header {{ padding-top: 32px; }}
      .toolbar {{ grid-template-columns: 1fr; }}
      .filters {{ width: 100%; display: grid; grid-template-columns: repeat(4, 1fr); }}
      .filters button {{ padding: 0 8px; }}
      .grid {{ grid-template-columns: 1fr; }}
      .card-head {{ flex-direction: column; align-items: flex-start; }}
      .badge {{ flex: initial; }}
    }}
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <p class="eyebrow">{html.escape(str(SKILLS_DIR))}</p>
      <h1>Skill 触发词总览</h1>
      <p class="lead">这份 HTML 从目录内可读取的 <code>SKILL.md</code> 生成，并按 skill 名去重。每张卡片列出自然语言触发词、用途描述和所有来源路径；符号链接会显示真实目标，方便判断它来自本仓库还是运行时 skill 目录。</p>
      <div class="stats" aria-label="技能统计">
        <div class="stat"><strong>{total_skills}</strong><span>去重后 skill 数</span></div>
        <div class="stat"><strong>{has_local}</strong><span>含本地/链接路径</span></div>
        <div class="stat"><strong>{has_download}</strong><span>含下载路径</span></div>
        <div class="stat"><strong>{symlink_count}</strong><span>符号链接路径</span></div>
      </div>
    </header>

    <section class="toolbar" aria-label="筛选工具">
      <input id="search" class="search" type="search" placeholder="搜索 skill、描述、路径或触发词" autocomplete="off">
      <div class="filters" role="group" aria-label="来源筛选">
        <button class="active" data-filter="all" type="button">全部</button>
        <button data-filter="skills-local" type="button">本地</button>
        <button data-filter="skills-download" type="button">下载</button>
        <button data-filter="mixed" type="button">重复</button>
      </div>
    </section>

    <main>
      <section id="grid" class="grid" aria-label="Skill 列表">
        {"".join(cards)}
      </section>
      <div id="empty" class="empty">没有匹配的 skill。</div>
    </main>

    <footer>
      生成时间：{html.escape(now)}。触发词来自 frontmatter description、triggers 和 <code>agents/openai.yaml</code> 默认提示的规则提取；后续维护时优先更新对应 <code>SKILL.md</code> 的 description。
    </footer>
  </div>

  <script>
    const search = document.querySelector('#search');
    const buttons = [...document.querySelectorAll('[data-filter]')];
    const cards = [...document.querySelectorAll('.skill-card')];
    const empty = document.querySelector('#empty');
    let activeFilter = 'all';

    function applyFilters() {{
      const q = search.value.trim().toLowerCase();
      let shown = 0;
      for (const card of cards) {{
        const groupOK = activeFilter === 'all' || card.dataset.group === activeFilter;
        const textOK = !q || card.dataset.text.includes(q);
        const visible = groupOK && textOK;
        card.hidden = !visible;
        if (visible) shown += 1;
      }}
      empty.style.display = shown ? 'none' : 'block';
    }}

    search.addEventListener('input', applyFilters);
    for (const btn of buttons) {{
      btn.addEventListener('click', () => {{
        activeFilter = btn.dataset.filter;
        for (const item of buttons) item.classList.toggle('active', item === btn);
        applyFilters();
      }});
    }}
  </script>
</body>
</html>'''

    return html_template


def main():
    print("正在收集 skills...")
    skills = find_skills()
    print(f"找到 {len(skills)} 个 skills")

    print("正在生成 HTML...")
    html_content = build_html(skills)

    print(f"正在写入 {OUTPUT_HTML}...")
    OUTPUT_HTML.write_text(html_content, encoding="utf-8")

    print("完成！")


if __name__ == "__main__":
    main()
