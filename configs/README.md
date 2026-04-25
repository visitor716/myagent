# 配置文件 Source of Truth

本目录保存 Claude Code 和 Codex 的配置模板，作为 source of truth 便于备份、恢复和多环境同步。

## 目录结构

```text
configs/
├── README.md
├── .gitignore                  # 忽略包含真实密钥的文件
├── sync.sh                     # 同步脚本
├── claude-code/
│   ├── settings.json           # Claude Code 配置模板（已脱敏）
│   └── .env.example            # 环境变量示例
└── codex/
    ├── config.toml             # Codex 配置模板
    ├── bash_aliases.full-auto.sh # Codex 全自动 bash 入口模板
    └── .env.example            # 环境变量示例
```

## 快速开始

### 1. 验证配置格式

```bash
bash configs/sync.sh validate
```

### 2. 从 myagent 恢复配置到运行时

```bash
bash configs/sync.sh restore
```

这会将 `configs/claude-code/settings.json` 复制到 `~/.claude/settings.json`，
将 `configs/codex/config.toml` 复制到 `~/.codex/config.toml`。

### 3. 安装 Codex 全自动默认入口

```bash
bash configs/sync.sh codex-full-auto
```

这会幂等更新：

- `configs/codex/config.toml` 和 `~/.codex/config.toml`
- `~/.bash_aliases` 中 marker 管理的 Codex 包装器块

安装后新开一个 WSL/Windows Terminal bash 窗口，`code x` 和 `codex` 默认进入
`--dangerously-bypass-approvals-and-sandbox` 模式；`cfa` 保留为较安全的 `--full-auto`
入口。

### 4. 备份运行时配置到 myagent

```bash
bash configs/sync.sh backup
```

**⚠️ 重要：** 备份后请检查配置文件中的敏感信息（如 API Key、Token 等），
确保已替换为占位符（如 `${ANTHROPIC_AUTH_TOKEN}`）后再提交到 git。

## 脱敏指南

备份后，请检查并替换以下敏感信息：

### Claude Code (`configs/claude-code/settings.json`)

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${ANTHROPIC_AUTH_TOKEN}",
    "ANTHROPIC_BASE_URL": "${ANTHROPIC_BASE_URL}"
  }
}
```

### Codex (`configs/codex/config.toml`)

Codex 配置通常不包含敏感 token，但如有 `auth_token` 等字段也需替换。

本仓库的 Codex 模板默认包含：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"

[notice]
hide_full_access_warning = true
```

这对应无审批、无沙箱的本地全自动入口，只应在受信任机器上恢复或安装。

## 环境变量

运行时可以通过 `.env` 文件注入环境变量：

```bash
# 复制示例文件
cp configs/claude-code/.env.example configs/claude-code/.env

# 编辑填入真实值
vim configs/claude-code/.env
```

**注意：** `.env` 文件已被 `.gitignore` 忽略，不会被提交。

## 安全提醒

- **永远不要**将包含真实 API Key 的配置文件提交到 git
- 本仓库中的配置模板已经过脱敏处理
- 使用 `${VAR_NAME}` 作为占位符
- 真实密钥应通过环境变量或本地 `.env` 文件管理
