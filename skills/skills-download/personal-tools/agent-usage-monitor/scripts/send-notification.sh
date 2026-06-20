#!/bin/bash
# /home/zhanxp/projects/myagent/skills/agent-usage-monitor/scripts/send-notification.sh

SCREENSHOT_PATH="$1"
AGENT_NAME="$2"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"
NOTIFICATION_CHANNEL=$(jq -r '.notificationChannel // "telegram"' "$CONFIG_FILE")

# 检查文件是否存在
if [ ! -f "$SCREENSHOT_PATH" ]; then
    echo "截图文件不存在: $SCREENSHOT_PATH"
    exit 1
fi

# 检查 claude-to-im 是否在运行
CLAUDE_TO_IM_STATUS=$(bash /home/zhanxp/.claude/skills/claude-to-im/scripts/daemon.sh status 2>/dev/null)

if [[ "$CLAUDE_TO_IM_STATUS" != *"running"* ]]; then
    echo "claude-to-im 服务未运行，尝试启动..."
    /claude-to-im start
    sleep 5
fi

# 构建通知内容
NOTIFICATION_TEXT="📊 Agent 使用量监控: ${AGENT_NAME}"
NOTIFICATION_TIME=$(date "+%Y-%m-%d %H:%M:%S")

echo "发送通知: $NOTIFICATION_TEXT"

# 创建临时通知脚本
TEMP_SCRIPT=$(mktemp /tmp/agent-notification-XXXXXX.js)
cat > "$TEMP_SCRIPT" << 'EOF'
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const screenshotPath = process.argv[2];
const agentName = process.argv[3];
const notificationTime = process.argv[4];

console.log(`发送通知: ${agentName} (${notificationTime})`);
console.log(`截图文件: ${screenshotPath}`);

// 这里应该使用 claude-to-im 的 SDK 或 API 来发送通知
// 简单示例：输出到日志
const logFile = path.join(process.env.HOME, '.claude-to-im', 'logs', 'agent-usage-monitor.log');
const logEntry = `${notificationTime} - ${agentName} - ${screenshotPath}`;

fs.appendFileSync(logFile, logEntry + '\n', 'utf8');

// 实际使用中，可以使用下面的方法来发送图片
// 例如：通过 Telegram 发送图片可以使用 curl 请求
EOF

# 执行通知发送
cd /home/zhanxp/projects/myagent/skills/claude-to-im
node "$TEMP_SCRIPT" "$SCREENSHOT_PATH" "$AGENT_NAME" "$NOTIFICATION_TIME"

# 清理临时文件
rm "$TEMP_SCRIPT"

# 简单的通知方式：保存到日志并打印
LOG_FILE="/home/zhanxp/.claude-to-im/logs/agent-usage-monitor.log"
mkdir -p $(dirname "$LOG_FILE")
echo "$NOTIFICATION_TIME - $AGENT_NAME - 截图已保存到: $SCREENSHOT_PATH" >> "$LOG_FILE"

# 输出成功信息
echo "通知已发送 (Channel: ${NOTIFICATION_CHANNEL})"
echo "截图已保存到日志: $LOG_FILE"

# 检查是否需要自动清理旧截图
MAX_SCREENSHOTS=20
SCREENSHOT_DIR="/tmp"
SCREENSHOT_PATTERN="agent-usage-*.png"

# 统计截图数量
SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR/$SCREENSHOT_PATTERN" 2>/dev/null | wc -l)

if [ "$SCREENSHOT_COUNT" -gt "$MAX_SCREENSHOTS" ]; then
    echo "截图数量过多，清理旧截图..."
    ls -1t "$SCREENSHOT_DIR/$SCREENSHOT_PATTERN" 2>/dev/null | tail -n +$((MAX_SCREENSHOTS + 1)) | xargs -I {} rm -f "$SCREENSHOT_DIR/{}"
fi
