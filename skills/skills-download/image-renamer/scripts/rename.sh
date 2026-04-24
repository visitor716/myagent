#!/bin/bash
# 图片智能重命名入口脚本

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$SKILL_DIR/scripts/image_renamer.py"

# 检查 Python 脚本是否存在
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "错误: Python 脚本不存在: $SCRIPT_PATH"
    exit 1
fi

# 检查 Python 是否可用
if ! command -v python3 &> /dev/null; then
    echo "错误: 未找到 python3"
    exit 1
fi

# 运行 Python 脚本
python3 "$SCRIPT_PATH" "$@"
