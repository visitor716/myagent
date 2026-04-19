#!/usr/bin/env bash
# Claude-to-IM 桥接监控脚本
# 定期检查进程是否存在，不存在则自动重启

CTI_HOME="${CTI_HOME:-$HOME/.claude-to-im}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$CTI_HOME/runtime/bridge.pid"
LOG_FILE="$CTI_HOME/logs/monitor.log"
DAEMON_SH="$SKILL_DIR/scripts/daemon.sh"

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 检查进程是否存活
check_and_restart() {
    log "INFO" "开始检查 Claude-to-IM 桥接进程"

    # 检查 PID 文件是否存在
    if [ -f "$PID_FILE" ]; then
        local PID=$(cat "$PID_FILE" 2>/dev/null)

        if [ -n "$PID" ]; then
            # 检查进程是否存在
            if kill -0 "$PID" 2>/dev/null; then
                log "INFO" "Claude-to-IM 桥接进程正在运行 (PID: $PID)"
                return 0
            else
                log "WARN" "PID 文件存在但进程不存在，清理 PID 文件"
                rm -f "$PID_FILE"
            fi
        fi
    fi

    # 进程不存在，启动桥接
    log "ERROR" "Claude-to-IM 桥接进程未运行，正在启动..."
    if bash "$DAEMON_SH" start; then
        log "INFO" "Claude-to-IM 桥接成功启动"
    else
        log "ERROR" "Claude-to-IM 桥接启动失败"
    fi
}

# 主函数
main() {
    # 检查是否传入了循环参数
    local loop=${1:-false}

    if [ "$loop" = "true" ]; then
        log "INFO" "监控模式启动，每 30 秒检查一次"
        while true; do
            check_and_restart
            sleep 30
        done
    else
        check_and_restart
    fi
}

# 检查是否被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
