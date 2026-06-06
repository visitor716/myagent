#!/usr/bin/env bash
#
# record-agent-task-md.sh - 录制 agent 任务并保存为 Markdown 文件
#
# Usage:
#   record-agent-task-md.sh \
#     --task-id task-20260605-001 \
#     --worker cc3 \
#     --title "修复任务详情终端流" \
#     --cwd /home/zhanxp/worktrees/tg-agent-gateway/cc3 \
#     -- claude
#
# Optional:
#   --dry-run          只打印输出路径，不执行录制
#   --out-dir <dir>    覆盖默认输出目录
#

set -euo pipefail

# 默认输出目录
DEFAULT_OUT_DIR="/mnt/d/Obsidian/MyNote/04.数字游民/1、开发/项目/tg-agent-gateway/worker执行任务"

# 颜色输出（仅用于终端显示，不写入文件）
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# 清理函数：移除 ANSI 控制序列
strip_ansi() {
  # 使用 Perl 移除 ANSI escape sequences
  # 参考: https://stackoverflow.com/a/18000433
  perl -pe '
    s/\033\[[0-9;]*[a-zA-Z]//g;
    s/\033\]0;[^\007]*\007//g;
    s/\033\][0-9;]*[a-zA-Z]//g;
  ' "$@"
}

# 清理文件名中的非法字符
sanitize_filename() {
  local name="$1"
  # 替换 Windows 非法字符: \/:*?"<>|
  echo "$name" | sed -e 's/[\\/:*?"<>|]/_/g'
}

# 显示使用说明
usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS] -- <command>

${BOLD}Required Options:${RESET}
  --task-id <id>     任务 ID (例如: task-20260605-001)
  --worker <name>    Worker 名称 (例如: cc3)
  --title <title>    任务标题
  --cwd <dir>        工作目录

${BOLD}Optional Options:${RESET}
  --dry-run          只打印输出路径，不执行录制
  --out-dir <dir>    覆盖默认输出目录
  -h, --help         显示此帮助

${BOLD}Example:${RESET}
  $(basename "$0") \\
    --task-id task-20260605-001 \\
    --worker cc3 \\
    --title "修复任务详情终端流" \\
    --cwd /home/zhanxp/worktrees/tg-agent-gateway/cc3 \\
    -- claude

EOF
  exit 1
}

# 解析命令行参数
parse_args() {
  TASK_ID=""
  WORKER=""
  TITLE=""
  CWD=""
  DRY_RUN=0
  OUT_DIR=""
  COMMAND=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)
        TASK_ID="$2"
        shift 2
        ;;
      --worker)
        WORKER="$2"
        shift 2
        ;;
      --title)
        TITLE="$2"
        shift 2
        ;;
      --cwd)
        CWD="$2"
        shift 2
        ;;
      --out-dir)
        OUT_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        ;;
      --)
        shift
        COMMAND=("$@")
        break
        ;;
      *)
        echo "${RED}Error:${RESET} Unknown option $1" >&2
        usage
        ;;
    esac
  done

  # 验证必填参数
  if [[ -z "$TASK_ID" || -z "$WORKER" || -z "$TITLE" || -z "$CWD" ]]; then
    echo "${RED}Error:${RESET} --task-id, --worker, --title, and --cwd are required" >&2
    usage
  fi

  if [[ ${#COMMAND[@]} -eq 0 ]]; then
    echo "${RED}Error:${RESET} Command is required after --" >&2
    usage
  fi

  # 设置输出目录
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$DEFAULT_OUT_DIR"
  fi

  # 添加年月子目录
  local year=$(date +%Y)
  local month=$(date +%m)
  OUT_DIR="$OUT_DIR/$year/$month"
}

# 生成输出文件路径
generate_paths() {
  local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  local safe_title=$(sanitize_filename "$TITLE")
  local filename="${timestamp}__${TASK_ID}__${WORKER}__${safe_title}.md"
  OUT_FILE="$OUT_DIR/$filename"
  ANSI_LOG=$(mktemp /tmp/record-agent-XXXXXX.ansi.log)
}

# 创建输出目录
ensure_out_dir() {
  if [[ ! -d "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
    echo "${BLUE}Created directory:${RESET} $OUT_DIR"
  fi
}

# 生成 Markdown 内容
generate_markdown() {
  local started_at="$1"
  local finished_at="$2"
  local exit_code="$3"
  local transcript_file="$4"

  local command_str="${COMMAND[*]}"

  cat <<EOF
# $TITLE

## Metadata
- Task ID: $TASK_ID
- Worker: $WORKER
- CWD: $CWD
- Command: $command_str
- Started At: $started_at
- Finished At: $finished_at
- Exit Code: $exit_code

## Terminal Transcript

\`\`\`text
EOF
  # 插入清理后的终端输出
  if [[ -f "$transcript_file" ]]; then
    # 移除最后一个换行符（如果有）以避免空行
    strip_ansi "$transcript_file" | sed -e '$a\'
  else
    echo "(No output captured)"
  fi

  cat <<EOF
\`\`\`
EOF
}

# 主函数
main() {
  parse_args "$@"
  generate_paths

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "${GREEN}Dry run:${RESET}"
    echo "  Output file: $OUT_FILE"
    echo "  Command: ${COMMAND[*]}"
    echo "  CWD: $CWD"
    echo "  Worker: $WORKER"
    echo "  Task ID: $TASK_ID"
    return 0
  fi

  # 确认工作目录存在
  if [[ ! -d "$CWD" ]]; then
    echo "${RED}Error:${RESET} CWD does not exist: $CWD" >&2
    exit 1
  fi

  ensure_out_dir

  echo "${GREEN}Recording to:${RESET} $OUT_FILE"
  echo "${BLUE}Command:${RESET} ${COMMAND[*]}"
  echo "${BLUE}CWD:${RESET} $CWD"
  echo "---"

  local started_at=$(date +"%Y-%m-%d %H:%M:%S")
  local exit_code=0

  # 使用 script 录制命令输出
  # -q: quiet
  # -f: flush output immediately
  # -c: command to run
  cd "$CWD" || exit 1

  if ! script -q -f -c "${COMMAND[*]}" "$ANSI_LOG"; then
    exit_code=$?
  fi

  local finished_at=$(date +"%Y-%m-%d %H:%M:%S")

  # 生成 Markdown 文件
  generate_markdown "$started_at" "$finished_at" "$exit_code" "$ANSI_LOG" > "$OUT_FILE"

  # 清理临时文件
  rm -f "$ANSI_LOG"

  echo "---"
  echo "${GREEN}Done!${RESET}"
  echo "  Output saved to: $OUT_FILE"
  echo "  Exit code: $exit_code"

  return "$exit_code"
}

# 只在直接运行时执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
