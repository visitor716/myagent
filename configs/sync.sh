#!/bin/bash
# ============================================================
# Claude Code / Codex 配置同步脚本
# ============================================================
# 用法:
#   ./sync.sh backup   - 将运行时配置备份到 myagent
#   ./sync.sh restore  - 将 myagent 配置恢复到运行时目录
#   ./sync.sh validate - 验证配置格式
#   ./sync.sh codex-full-auto - 安装 Codex 全自动默认入口
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CLAUDE_RUNTIME="$HOME/.claude/settings.json"
CLAUDE_SOURCE="$SCRIPT_DIR/claude-code/settings.json"
CODEX_RUNTIME="$HOME/.codex/config.toml"
CODEX_SOURCE="$SCRIPT_DIR/codex/config.toml"
CODEX_ALIAS_RUNTIME="$HOME/.bash_aliases"
CODEX_ALIAS_SOURCE="$SCRIPT_DIR/codex/bash_aliases.full-auto.sh"
CODEX_FULL_AUTO_BLOCK_START="# >>> codex full-auto defaults >>>"
CODEX_FULL_AUTO_BLOCK_END="# <<< codex full-auto defaults <<<"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

backup_file() {
    local file="$1"
    local label="$2"

    if [[ -f "$file" ]]; then
        cp "$file" "$file.bak.$BACKUP_STAMP"
        log_info "已创建${label}备份: $file.bak.$BACKUP_STAMP"
    fi
}

write_if_changed() {
    local tmp_file="$1"
    local target="$2"
    local label="$3"
    local mode="${4:-}"

    mkdir -p "$(dirname "$target")"

    if [[ -f "$target" ]] && cmp -s "$tmp_file" "$target"; then
        rm -f "$tmp_file"
        log_info "$label 无需更新: $target"
        return 0
    fi

    backup_file "$target" "$label"
    mv "$tmp_file" "$target"

    if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
    fi

    log_success "$label 已更新: $target"
}

upsert_toml_root_key_in_place() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp_file
    tmp_file="$(mktemp)"

    awk -v key="$key" -v replacement="$key = $value" '
        BEGIN { done = 0; in_root = 1 }
        in_root && /^[[:space:]]*\[/ {
            if (!done) {
                print replacement
                done = 1
            }
            in_root = 0
        }
        in_root && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!done) {
                print replacement
                done = 1
            }
            next
        }
        { print }
        END {
            if (!done) {
                print replacement
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

upsert_toml_table_key_in_place() {
    local file="$1"
    local table="$2"
    local key="$3"
    local value="$4"
    local tmp_file
    tmp_file="$(mktemp)"

    awk -v table="$table" -v key="$key" -v replacement="$key = $value" '
        BEGIN { in_table = 0; seen_table = 0; done = 0 }
        /^[[:space:]]*\[/ {
            if (in_table && !done) {
                print replacement
                done = 1
            }
            in_table = ($0 == table)
            if (in_table) {
                seen_table = 1
            }
            print
            next
        }
        in_table && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!done) {
                print replacement
                done = 1
            }
            next
        }
        { print }
        END {
            if (in_table && !done) {
                print replacement
            }
            if (!seen_table) {
                if (NR > 0) {
                    print ""
                }
                print table
                print replacement
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

install_codex_full_auto_config() {
    local target="$1"
    local label="$2"
    local mode="$3"
    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -f "$target" ]]; then
        cp "$target" "$tmp_file"
    else
        : > "$tmp_file"
    fi

    upsert_toml_root_key_in_place "$tmp_file" "approval_policy" '"never"'
    upsert_toml_root_key_in_place "$tmp_file" "sandbox_mode" '"danger-full-access"'
    upsert_toml_table_key_in_place "$tmp_file" "[notice]" "hide_full_access_warning" "true"
    write_if_changed "$tmp_file" "$target" "$label" "$mode"
}

install_codex_full_auto_aliases() {
    if [[ ! -f "$CODEX_ALIAS_SOURCE" ]]; then
        log_error "Codex 全自动 bash 入口模板不存在: $CODEX_ALIAS_SOURCE"
        exit 1
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -f "$CODEX_ALIAS_RUNTIME" ]]; then
        if grep -Fxq "$CODEX_FULL_AUTO_BLOCK_START" "$CODEX_ALIAS_RUNTIME" &&
            grep -Fxq "$CODEX_FULL_AUTO_BLOCK_END" "$CODEX_ALIAS_RUNTIME"; then
            awk \
                -v start="$CODEX_FULL_AUTO_BLOCK_START" \
                -v end="$CODEX_FULL_AUTO_BLOCK_END" \
                -v block="$CODEX_ALIAS_SOURCE" '
                $0 == start {
                    while ((getline line < block) > 0) {
                        print line
                    }
                    close(block)
                    skip = 1
                    next
                }
                skip && $0 == end {
                    skip = 0
                    next
                }
                !skip { print }
            ' "$CODEX_ALIAS_RUNTIME" > "$tmp_file"
        else
            cp "$CODEX_ALIAS_RUNTIME" "$tmp_file"
            {
                echo ""
                cat "$CODEX_ALIAS_SOURCE"
            } >> "$tmp_file"
        fi
    else
        cp "$CODEX_ALIAS_SOURCE" "$tmp_file"
    fi

    write_if_changed "$tmp_file" "$CODEX_ALIAS_RUNTIME" "Codex bash 入口" "644"
}

# 验证 JSON 格式
validate_json() {
    local file="$1"
    if command -v jq &> /dev/null; then
        jq empty "$file" 2>/dev/null && return 0 || return 1
    else
        # 简单验证：检查是否以 { 开头
        [[ $(head -c 1 "$file") == "{" ]] && return 0 || return 1
    fi
}

# 验证 TOML 格式
validate_toml() {
    local file="$1"
    # 简单验证：检查是否包含等号或方括号
    grep -qE '^[a-zA-Z_]+\s*=|^\[' "$file" && return 0 || return 1
}

cmd_backup() {
    log_info "开始备份运行时配置到 myagent..."

    # 备份 Claude Code
    if [[ -f "$CLAUDE_RUNTIME" ]]; then
        cp "$CLAUDE_RUNTIME" "$CLAUDE_SOURCE"
        log_success "Claude Code 配置已备份: $CLAUDE_SOURCE"
        log_warn "注意: 备份文件中可能包含敏感信息，请检查并脱敏后再提交"
    else
        log_error "Claude Code 运行时配置不存在: $CLAUDE_RUNTIME"
        exit 1
    fi

    # 备份 Codex
    if [[ -f "$CODEX_RUNTIME" ]]; then
        cp "$CODEX_RUNTIME" "$CODEX_SOURCE"
        log_success "Codex 配置已备份: $CODEX_SOURCE"
    else
        log_error "Codex 运行时配置不存在: $CODEX_RUNTIME"
        exit 1
    fi

    echo ""
    log_warn "⚠️  备份完成！请务必检查配置文件中的敏感信息（API Key、Token 等）"
    log_warn "   并已脱敏处理后再提交到 git。"
}

cmd_restore() {
    log_info "开始从 myagent 恢复配置到运行时目录..."

    # 恢复 Claude Code
    if [[ -f "$CLAUDE_SOURCE" ]]; then
        # 创建备份
        if [[ -f "$CLAUDE_RUNTIME" ]]; then
            cp "$CLAUDE_RUNTIME" "$CLAUDE_RUNTIME.bak.$(date +%Y%m%d_%H%M%S)"
            log_info "已创建原配置备份"
        fi
        cp "$CLAUDE_SOURCE" "$CLAUDE_RUNTIME"
        log_success "Claude Code 配置已恢复到: $CLAUDE_RUNTIME"
    else
        log_error "myagent 中不存在 Claude Code 配置: $CLAUDE_SOURCE"
        exit 1
    fi

    # 恢复 Codex
    if [[ -f "$CODEX_SOURCE" ]]; then
        # 创建备份
        if [[ -f "$CODEX_RUNTIME" ]]; then
            cp "$CODEX_RUNTIME" "$CODEX_RUNTIME.bak.$(date +%Y%m%d_%H%M%S)"
            log_info "已创建原配置备份"
        fi
        cp "$CODEX_SOURCE" "$CODEX_RUNTIME"
        log_success "Codex 配置已恢复到: $CODEX_RUNTIME"
    else
        log_error "myagent 中不存在 Codex 配置: $CODEX_SOURCE"
        exit 1
    fi
}

cmd_codex_full_auto() {
    log_warn "将启用 Codex 无审批、无沙箱默认入口。仅在你信任当前系统环境时使用。"

    install_codex_full_auto_config "$CODEX_SOURCE" "Codex 模板配置" "644"
    install_codex_full_auto_config "$CODEX_RUNTIME" "Codex 运行时配置" "600"
    install_codex_full_auto_aliases

    log_success "Codex 全自动默认入口已安装"
    log_info "新开一个 WSL/Windows Terminal bash 窗口后，可用: code x 或 codex"
}

cmd_validate() {
    log_info "验证配置格式..."
    local has_error=0

    # 验证 Claude Code
    if [[ -f "$CLAUDE_SOURCE" ]]; then
        if validate_json "$CLAUDE_SOURCE"; then
            log_success "Claude Code 配置格式正确"
        else
            log_error "Claude Code 配置格式错误: $CLAUDE_SOURCE"
            has_error=1
        fi
    else
        log_warn "Claude Code 配置不存在: $CLAUDE_SOURCE"
    fi

    # 验证 Codex
    if [[ -f "$CODEX_SOURCE" ]]; then
        if validate_toml "$CODEX_SOURCE"; then
            log_success "Codex 配置格式正确"
        else
            log_error "Codex 配置格式错误: $CODEX_SOURCE"
            has_error=1
        fi
    else
        log_warn "Codex 配置不存在: $CODEX_SOURCE"
    fi

    # 验证 Codex bash 入口模板
    if [[ -f "$CODEX_ALIAS_SOURCE" ]]; then
        if bash -n "$CODEX_ALIAS_SOURCE"; then
            log_success "Codex 全自动 bash 入口模板语法正确"
        else
            log_error "Codex 全自动 bash 入口模板语法错误: $CODEX_ALIAS_SOURCE"
            has_error=1
        fi
    else
        log_warn "Codex 全自动 bash 入口模板不存在: $CODEX_ALIAS_SOURCE"
    fi

    if [[ $has_error -eq 0 ]]; then
        log_success "所有验证通过"
        return 0
    else
        return 1
    fi
}

show_help() {
    echo "Claude Code / Codex 配置同步脚本"
    echo ""
    echo "用法: $0 <command>"
    echo ""
    echo "命令:"
    echo "  backup           将运行时配置备份到 myagent (需手动脱敏)"
    echo "  restore          将 myagent 配置恢复到运行时目录"
    echo "  codex-full-auto  安装 Codex 全自动默认入口到模板和运行时"
    echo "  validate         验证配置格式"
    echo "  help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 codex-full-auto"
    echo "  $0 validate"
}

# 主入口
case "${1:-help}" in
    backup)
        cmd_backup
        ;;
    restore)
        cmd_restore
        ;;
    codex-full-auto)
        cmd_codex_full_auto
        ;;
    validate)
        cmd_validate
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "未知命令: $1"
        show_help
        exit 1
        ;;
esac
