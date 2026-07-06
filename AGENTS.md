# 仓库指南

## 项目结构

这是我在学习和使用 AI 过程中沉淀的宝贵资产仓库，保存所有值得保留的内容：
- `skills/skills-local/` - 本地自定义技能（主要工作区）
- `skills/skills-download/` - 下载/管理的技能
- `configs/` - Claude Code + Codex 配置模板
- `scripts/` - Windows/WSL 工具脚本
- `docs/` - 迁移计划和状态文档

## 验证命令

```bash
bash configs/sync.sh validate    # 验证配置格式
bash configs/sync.sh restore     # 模板 → 运行时
bash configs/sync.sh backup      # 运行时 → 模板（备份后需脱敏）
```

## 执行原则

1. 先将需求转化为具体的成功标准和验证证据
2. 做最小且足够的改动，避免不必要的抽象和依赖
3. 保持修改的精准性，只触摸与需求相关的文件
4. 用实际执行结果验证，而非凭信心
5. 优先可逆的改动

## 编码规范

- 文档用 Markdown，指令简洁直接
- Shell 脚本使用 `set -euo pipefail`，变量加引号，保持幂等
- Python 优先使用标准库，函数清晰，路径显式
- 技能目录名用小写连字符格式，如 `daily-report-table`

## 安全规则

- 永远不要提交真实的 API Key、Token 或本地密钥
- 使用 `${VAR_NAME}` 占位符
- `~/.codex/skills/` 和 `~/.claude/skills/` 是运行时挂载点，不是主存储

## Codex 运行偏好

本机使用高自治模式：`approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`，除非用户明确要求降低权限。

浏览器自动化使用 `wsl-windows-chrome` 技能的专用 Windows Chrome/Edge 配置文件。

从 WSL 调用 Windows PowerShell/PowerShell 7 时，优先使用 `powershell-skill`；该技能通过 EncodedCommand helper 传入脚本，默认选择最新版 `pwsh.exe`，避免 Bash 与 PowerShell 双重引号解析。简单一行命令才直接使用 `powershell.exe -Command '...'`。

长期记忆保存在 `docs/agent-memory/` 下。
