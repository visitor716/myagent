#!/bin/bash
# /home/zhanxp/projects/myagent/skills/agent-usage-monitor/scripts/monitor.sh

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在: $CONFIG_FILE"
    echo "请先运行 /agent-usage-monitor setup 进行初始化"
    exit 1
fi

# 读取配置
AGENTS=($(jq -r '.agents[] | select(.enabled == true) | .id' "$CONFIG_FILE"))

# 检查是否有启用的 Agent
if [ ${#AGENTS[@]} -eq 0 ]; then
    echo "没有启用的 Agent 配置"
    exit 0
fi

# 连接到 Chrome 浏览器
echo "连接到 Chrome 浏览器..."
bash /home/zhanxp/.claude/skills/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh \
  --attach-only --session agent-monitor

if [ $? -ne 0 ]; then
    echo "无法连接到 Chrome 浏览器"
    exit 1
fi

# 遍历每个 Agent 进行截图
for AGENT_ID in "${AGENTS[@]}"; do
    AGENT_NAME=$(jq -r ".agents[] | select(.id == \"$AGENT_ID\") | .name" "$CONFIG_FILE")
    AGENT_URL=$(jq -r ".agents[] | select(.id == \"$AGENT_ID\") | .url" "$CONFIG_FILE")
    SCREENSHOT_DELAY=$(jq -r '.screenshotDelay // 2000' "$CONFIG_FILE")

    echo "正在处理: $AGENT_NAME"

    # 导航到目标页面
    if ! playwright-cli -s=agent-monitor goto "$AGENT_URL"; then
        echo "无法导航到页面: $AGENT_URL"
        continue
    fi

    # 等待页面加载
    sleep $((SCREENSHOT_DELAY / 1000))

    # 创建截图文件名
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    SCREENSHOT_PATH="/tmp/agent-usage-${AGENT_ID}-${TIMESTAMP}.png"

    # 截图
    if ! playwright-cli -s=agent-monitor snapshot "$SCREENSHOT_PATH"; then
        echo "截图失败: $SCREENSHOT_PATH"
        continue
    fi

    echo "截图已保存: $SCREENSHOT_PATH"

    # 发送通知
    if [ -f "$SCREENSHOT_PATH" ]; then
        bash "$SKILL_DIR/scripts/send-notification.sh" "$SCREENSHOT_PATH" "$AGENT_NAME"
    fi
done

echo "监控任务完成"
