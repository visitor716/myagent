#!/bin/bash
# /home/zhanxp/projects/myagent/skills/agent-usage-monitor/scripts/status.sh

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

echo "=== Agent 使用量监控工具状态检查 ==="
echo ""

# 检查技能目录
if [ -d "$SKILL_DIR" ]; then
    echo "✅ 技能目录存在: $SKILL_DIR"
else
    echo "❌ 技能目录不存在: $SKILL_DIR"
fi

echo ""

# 检查配置文件
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ 配置文件存在: $CONFIG_FILE"

    # 检查配置文件格式
    if jq . "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✅ 配置文件格式正确"

        # 统计启用的 Agent 数量
        AGENT_COUNT=$(jq -r '.agents | length' "$CONFIG_FILE")
        ENABLED_COUNT=$(jq -r '.agents[] | select(.enabled == true) | .id' "$CONFIG_FILE" | wc -l)
        echo "ℹ️ Agent 配置: $AGENT_COUNT 个，其中 $ENABLED_COUNT 个已启用"
    else
        echo "❌ 配置文件格式错误"
    fi
else
    echo "❌ 配置文件不存在: $CONFIG_FILE"
    echo "ℹ️ 请运行 /agent-usage-monitor setup 进行初始化"
fi

echo ""

# 检查 Chrome 浏览器连接
echo "检查 Chrome 浏览器连接..."
BROWSER_STATUS=$(bash /home/zhanxp/.claude/skills/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --status --json)

if jq -e '.local_cdp_ready or .gateway_cdp_ready or .relay_cdp_ready' <<< "$BROWSER_STATUS" > /dev/null 2>&1; then
    echo "✅ Chrome 浏览器可访问"

    # 获取浏览器版本
    CDP_VERSION=$(bash /home/zhanxp/.claude/skills/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --status | grep -o 'Chrome/[^ ]*')
    if [ -n "$CDP_VERSION" ]; then
        echo "ℹ️ 浏览器版本: $CDP_VERSION"
    fi
else
    echo "❌ Chrome 浏览器不可访问"
    echo "ℹ️ 请确保已启动 Windows Chrome 自动化浏览器"
fi

echo ""

# 检查通知服务
echo "检查 claude-to-im 通知服务..."
NOTIFICATION_STATUS=$(bash /home/zhanxp/.claude/skills/claude-to-im/scripts/daemon.sh status 2>&1)

if [[ "$NOTIFICATION_STATUS" == *"running"* ]]; then
    echo "✅ claude-to-im 服务正在运行"
else
    echo "❌ claude-to-im 服务未运行"

    # 检查是否已配置
    if [ -f "$HOME/.claude-to-im/config.env" ]; then
        echo "ℹ️ 通知服务已配置，但未启动"
        echo "ℹ️ 运行 /claude-to-im start 启动服务"
    else
        echo "ℹ️ 通知服务未配置"
        echo "ℹ️ 运行 /claude-to-im setup 进行配置"
    fi
fi

echo ""

# 检查 Playwright CLI
if command -v playwright-cli &> /dev/null; then
    echo "✅ Playwright CLI 已安装"
else
    echo "❌ Playwright CLI 未安装"
fi

echo ""

# 检查 jq 工具
if command -v jq &> /dev/null; then
    echo "✅ jq 工具已安装"
else
    echo "❌ jq 工具未安装"
    echo "ℹ️ 请安装 jq: sudo apt-get install jq 或 brew install jq"
fi

echo ""
echo "=== 检查完成 ==="
