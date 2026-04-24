#!/bin/bash
# /home/zhanxp/projects/myagent/skills/agent-usage-monitor/scripts/setup.sh

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

# 检查配置文件是否已存在
if [ -f "$CONFIG_FILE" ]; then
    echo "配置文件已存在: $CONFIG_FILE"
    echo "是否要重新创建配置文件? (y/N)"
    read -r RESPONSE
    if [[ ! "$RESPONSE" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 创建配置目录
mkdir -p $(dirname "$CONFIG_FILE")

# 复制示例配置
cat > "$CONFIG_FILE" << 'EOF'
{
  "interval": 30,
  "screenshotDelay": 2000,
  "notificationChannel": "telegram",
  "agents": [
    {
      "id": "claude-sonnet-4-6",
      "name": "Claude Sonnet 4.6",
      "url": "https://claude.ai/usage",
      "usageSelector": ".usage-statistics",
      "enabled": true
    },
    {
      "id": "gpt-4-turbo",
      "name": "GPT-4 Turbo",
      "url": "https://platform.openai.com/account/usage",
      "usageSelector": "#usage-summary",
      "enabled": true
    }
  ]
}
EOF

# 设置文件权限
chmod 644 "$CONFIG_FILE"

# 检查并安装依赖
echo "检查依赖..."

# 检查是否有 jq
if ! command -v jq &> /dev/null; then
    echo "正在安装 jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo "jq 未找到，无法安装，请手动安装"
    fi
fi

# 检查 claude-to-im 技能
if [ ! -d "/home/zhanxp/.claude/skills/claude-to-im" ]; then
    echo "claude-to-im 技能未找到"
fi

# 检查 wsl-windows-chrome 技能
if [ ! -d "/home/zhanxp/.claude/skills/wsl-windows-chrome" ]; then
    echo "wsl-windows-chrome 技能未找到"
fi

# 完成
echo "✅ 初始化完成!"
echo ""
echo "配置文件已创建在: $CONFIG_FILE"
echo "你可以编辑该文件添加更多的 Agent 配置"
echo ""
echo "下一步操作:"
echo "1. 确保 claude-to-im 服务已配置并启动"
echo "2. 确保 wsl-windows-chrome 浏览器已连接"
echo "3. 使用 /loop 30m /agent-usage-monitor run 设置定时任务"
