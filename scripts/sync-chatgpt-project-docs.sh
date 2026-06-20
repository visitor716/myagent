#!/usr/bin/env bash
set -euo pipefail

# ============================================
# ChatGPT Project 文档自动同步脚本
# ============================================
# 功能：
# - 合并所有 chatgpt-project 文档到一个 bundle
# - 通过 opencli browser 自动上传到 ChatGPT Project
#
# 使用方法：
#   bash scripts/sync-chatgpt-project-docs.sh --project-url <url> [--dry-run] [--keep-tab]
#
# 参数：
#   --project-url <url>  ChatGPT Project URL（必填）
#   --dry-run            只生成 bundle，不上传
#   --keep-tab           同步完成后保留浏览器标签
#
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_DIR/docs/chatgpt-project"
BUNDLE_FILE="$DOCS_DIR/chatgpt-project-bundle.md"
BUNDLE_FILENAME="chatgpt-project-bundle.md"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 解析参数
PROJECT_URL=""
DRY_RUN=0
KEEP_TAB=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-url)
            PROJECT_URL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --keep-tab)
            KEEP_TAB=1
            shift
            ;;
        *)
            log_error "未知参数: $1"
            echo "使用方法: $0 --project-url <url> [--dry-run] [--keep-tab]"
            exit 1
            ;;
    esac
done

# 验证参数
if [[ -z "$PROJECT_URL" ]]; then
    log_error "必须指定 --project-url 参数"
    echo "使用方法: $0 --project-url <url> [--dry-run] [--keep-tab]"
    exit 1
fi

log_info "项目目录: $PROJECT_DIR"
log_info "文档目录: $DOCS_DIR"
log_info "目标 Project: $PROJECT_URL"
if [[ $DRY_RUN -eq 1 ]]; then
    log_warning "DRY RUN 模式：不会上传到 ChatGPT"
fi

# ============================================
# 步骤 1：刷新 CURRENT_CONTEXT.md
# ============================================
log_info "步骤 1/5: 刷新 CURRENT_CONTEXT.md"
if [[ -f "$SCRIPT_DIR/generate-chatgpt-context.sh" ]]; then
    bash "$SCRIPT_DIR/generate-chatgpt-context.sh" "$PROJECT_DIR"
else
    log_warning "generate-chatgpt-context.sh 不存在，跳过刷新"
fi

# ============================================
# 步骤 2：合并生成 bundle
# ============================================
log_info "步骤 2/5: 生成文档 bundle"

# 文档顺序（按重要性）
DOCS_ORDER=(
    "CHATGPT_PROJECT_INSTRUCTIONS.md"
    "PROJECT_OVERVIEW.md"
    "WORKFLOW_RULES.md"
    "COMMANDS.md"
    "ARCHITECTURE_MAP.md"
    "CURRENT_CONTEXT.md"
)

# 检查文档是否存在
MISSING_DOCS=()
for doc in "${DOCS_ORDER[@]}"; do
    if [[ ! -f "$DOCS_DIR/$doc" ]]; then
        MISSING_DOCS+=("$doc")
    fi
done

if [[ ${#MISSING_DOCS[@]} -gt 0 ]]; then
    log_warning "以下文档缺失: ${MISSING_DOCS[*]}"
fi

# 合并文档
{
    echo "# tg-agent-gateway ChatGPT Project Bundle"
    echo ""
    echo "> 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "> 此文件由 scripts/sync-chatgpt-project-docs.sh 自动生成"
    echo ""
    echo "---"
    echo ""

    for doc in "${DOCS_ORDER[@]}"; do
        if [[ -f "$DOCS_DIR/$doc" ]]; then
            echo "# ========================================"
            echo "# 文件: $doc"
            echo "# ========================================"
            echo ""
            cat "$DOCS_DIR/$doc"
            echo ""
            echo ""
            echo "---"
            echo ""
        fi
    done
} > "$BUNDLE_FILE"

log_success "Bundle 已生成: $BUNDLE_FILE"

# 显示 bundle 大小
BUNDLE_SIZE=$(wc -l < "$BUNDLE_FILE")
log_info "Bundle 大小: $BUNDLE_SIZE 行"

# ============================================
# 步骤 3：检查 opencli
# ============================================
log_info "步骤 3/5: 检查 opencli 环境"

if ! command -v opencli &> /dev/null; then
    log_error "opencli 未找到，请先安装 opencli"
    exit 1
fi

log_success "opencli 可用: $(which opencli)"

# 检查 opencli doctor（可选，不阻断）
if [[ $DRY_RUN -eq 0 ]]; then
    log_info "运行 opencli doctor..."
    if ! opencli doctor 2>&1 | head -20; then
        log_warning "opencli doctor 有警告，但继续尝试"
    fi
fi

# Dry Run 模式结束
if [[ $DRY_RUN -eq 1 ]]; then
    log_success "DRY RUN 完成！"
    echo ""
    echo "生成的文件："
    echo "  - $BUNDLE_FILE"
    echo ""
    echo "要真实同步，请去掉 --dry-run 参数"
    exit 0
fi

# ============================================
# 步骤 4：浏览器自动化 - 打开 Project
# ============================================
log_info "步骤 4/5: 打开 ChatGPT Project..."

# 生成一个临时 session 名称
SESSION_NAME="chatgpt-project-sync-$(date +%s)"

# 首先尝试打开 URL
log_info "正在打开: $PROJECT_URL"

# 这里使用 opencli browser
# 注意：实际 selector 需要根据 ChatGPT UI 调整
# 第一版采用诊断模式，先获取页面状态

if ! opencli browser "$SESSION_NAME" open "$PROJECT_URL"; then
    log_error "无法打开 ChatGPT Project 页面"
    echo ""
    echo "可能的原因："
    echo "  1. 未登录 ChatGPT，请先在浏览器中登录"
    echo "  2. URL 不正确，请确认 Project URL"
    echo "  3. opencli browser 桥接有问题"
    exit 1
fi

# 等待页面加载
log_info "等待页面加载..."
sleep 3

# 获取页面状态用于诊断
log_info "获取页面状态..."
if ! PAGE_STATE=$(opencli browser "$SESSION_NAME" state 2>&1); then
    log_error "无法获取页面状态"
    opencli browser "$SESSION_NAME" close || true
    exit 1
fi

# 输出诊断信息
echo ""
echo "=== 页面诊断信息 ==="
echo "URL: $(opencli browser "$SESSION_NAME" url 2>&1 || echo "无法获取 URL")"
echo "Title: $(opencli browser "$SESSION_NAME" title 2>&1 || echo "无法获取 Title")"
echo "State snippet:"
echo "$PAGE_STATE" | head -50
echo "==================="
echo ""

# ============================================
# 步骤 5：查找并更新 Sources
# ============================================
log_info "步骤 5/5: 更新 Project Sources..."

# 第一版：先尝试查找是否有上传区域
# 这里的 selector 需要根据实际 ChatGPT UI 调整
# 如果找不到，就提示用户

log_warning "第一版脚本：自动化更新功能正在开发中"
log_info "目前请手动上传 bundle 文件到 ChatGPT Project Sources"

echo ""
echo "============================================="
echo "手动更新指南："
echo "============================================="
echo "1. 在打开的 ChatGPT Project 页面中"
echo "2. 点击 \"Project settings\" 或设置图标"
echo "3. 找到 \"Sources\" 或 \"Knowledge\" 区域"
echo "4. 删除旧的 \"$BUNDLE_FILENAME\"（如果存在）"
echo "5. 上传新的 bundle 文件："
echo "   $BUNDLE_FILE"
echo "6. 保存设置"
echo ""
echo "Bundle 文件已生成，可以直接使用！"
echo "============================================="
echo ""

# 如果用户没有指定 --keep-tab，询问是否关闭
if [[ $KEEP_TAB -eq 0 ]]; then
    read -p "是否关闭浏览器标签？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        opencli browser "$SESSION_NAME" close || true
        log_info "标签已关闭"
    else
        log_info "保留浏览器标签"
    fi
else
    log_info "--keep-tab 已指定，保留浏览器标签"
fi

log_success "同步流程完成！"
echo ""
echo "生成的 bundle: $BUNDLE_FILE"
