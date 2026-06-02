# CLAUDE.md

本文件为 Claude Code 提供本仓库的工作指南。

## 仓库定位

这是我在学习和使用 AI 过程中沉淀的宝贵资产仓库，保存所有值得保留的内容：自定义 Agent 技能、配置模板、工具脚本、工作流笔记、浏览器/代理流程、持久化运行记忆。这不是传统软件项目——没有顶层构建、lint 或测试套件。

## 执行原则

1. 先将需求转化为具体的成功标准和验证证据
2. 做最小且足够的改动，避免新抽象、依赖、大范围重写或机会主义清理
3. 保持修改的精准性，只触摸与需求相关的文件，保留不相关的脏工作，优先可逆改动
4. 用实际执行结果验证：`bash configs/sync.sh validate`、Python 编译检查、Shell 语法检查、技能测试

## 仓库结构

```
skills/skills-local/     # 本地自定义技能（主要工作区）
skills/skills-download/  # 下载/管理的技能（OMX 管理，较少编辑）
configs/                 # Claude Code + Codex 配置模板 + sync.sh
scripts/                 # Windows/WSL 工具脚本
docs/                    # 迁移计划和状态文档
```

## 技能结构

每个技能在 `skills-local/` 下的布局：

```
<skill-name>/
├── SKILL.md              # 技能定义 —— 主要编辑文件
├── .skill-source.json    # 元数据（来源所有者、运行时目标、同步策略）
├── agents/openai.yaml    # 可选：OpenAI 兼容代理配置
├── scripts/              # 技能调用的实现脚本
├── references/           # 可选：技能加载的参考文档
└── tests/                # 可选：测试文件（目前只有 daily-report-table）
```

编辑技能时，`SKILL.md` 是入口点，脚本在 `scripts/` 中。

## 配置管理

```bash
bash configs/sync.sh validate          # 验证配置格式
bash configs/sync.sh restore           # 模板 → 运行时 (~/.claude/, ~/.codex/)
bash configs/sync.sh backup            # 运行时 → 模板（备份后需脱敏！）
bash configs/sync.sh codex-full-auto   # 安装 Codex 免审批、免沙箱别名
```

配置模板已脱敏——真实密钥在环境变量中，永远不提交。

## 关键规则

1. 只在 `skills/skills-local/` 内编辑自定义技能
2. 运行时目录（`~/.codex/skills/`、`~/.claude/skills/`）是挂载点，不是主存储
3. 永远不要提交真实的 API Key 或 Token，配置中使用 `${VAR_NAME}` 占位符
4. 运行 `configs/sync.sh backup` 后，提交前务必检查并脱敏密钥
5. 技能目录名使用小写连字符格式
