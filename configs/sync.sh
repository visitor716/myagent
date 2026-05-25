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
CLAUDE_CONFIG_RUNTIME="$HOME/.claude/config.json"
CLAUDE_GLOBAL_RUNTIME="$HOME/.claude.json"
CLAUDE_SOURCE_DIR="$SCRIPT_DIR/claude code"
CLAUDE_SOURCE="$CLAUDE_SOURCE_DIR/settings.json"
CLAUDE_CONFIG_SOURCE="$CLAUDE_SOURCE_DIR/config.json"
CLAUDE_GLOBAL_SOURCE="$CLAUDE_SOURCE_DIR/claude.json"
CODEX_RUNTIME="$HOME/.codex/config.toml"
CODEX_RUNTIME_DIR="$HOME/.codex"
CODEX_SOURCE="$SCRIPT_DIR/codex/config.toml"
CODEX_RUNTIME_BACKUP_DIR="$SCRIPT_DIR/codex/runtime"
CODEX_ALIAS_RUNTIME="$HOME/.bash_aliases"
CODEX_ALIAS_SOURCE="$SCRIPT_DIR/codex/bash_aliases.full-auto.sh"
CODEX_MEMORY_SOURCE="$PROJECT_DIR/docs/agent-memory/codex-operating-memory.md"
CODEX_MEMORY_RUNTIME="$HOME/.codex/memories/codex-operating-memory.md"
CODEX_SYSTEMD_SOURCE_DIR="$SCRIPT_DIR/codex/systemd"
CODEX_SYSTEMD_RUNTIME_DIR="$HOME/.config/systemd/user"
CODEX_FULL_AUTO_BLOCK_START="# >>> codex full-auto defaults >>>"
CODEX_FULL_AUTO_BLOCK_END="# <<< codex full-auto defaults <<<"
CODEX_DISABLED_STARTUP_MCP_TABLES=(
    "[mcp_servers.chrome-devtools]"
    "[mcp_servers.context7]"
)
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

copy_claude_json_sanitized() {
    local source="$1"
    local target="$2"

    if [[ ! -f "$source" ]]; then
        log_warn "Claude Code 配置不存在，跳过: $source"
        return 0
    fi

    if ! command -v node >/dev/null 2>&1; then
        log_error "需要 node 才能脱敏 Claude Code JSON: $source"
        exit 1
    fi

    mkdir -p "$(dirname "$target")"
    node - "$source" "$target" <<'NODE'
const fs = require('fs');

const [source, target] = process.argv.slice(2);

function sensitiveKey(key) {
  const norm = String(key).toLowerCase().replace(/[^a-z0-9]/g, '');
  return norm.endsWith('apikey') ||
    norm.endsWith('authtoken') ||
    norm.endsWith('authorization') ||
    norm.endsWith('bearertoken') ||
    norm.includes('secret') ||
    norm.includes('password') ||
    norm.includes('credential') ||
    norm === 'primaryapikey' ||
    norm.endsWith('accesstoken') ||
    norm.endsWith('refreshtoken');
}

function placeholderFor(key) {
  const upper = String(key).toUpperCase();
  if (upper === 'ANTHROPIC_API_KEY' || key === 'primaryApiKey') {
    return '${ANTHROPIC_API_KEY}';
  }
  if (upper === 'ANTHROPIC_AUTH_TOKEN') {
    return '${ANTHROPIC_AUTH_TOKEN}';
  }
  return '***REDACTED***';
}

function redact(value) {
  if (Array.isArray(value)) {
    return value.map(redact);
  }
  if (value && typeof value === 'object') {
    const output = {};
    for (const [key, child] of Object.entries(value)) {
      output[key] = sensitiveKey(key) ? placeholderFor(key) : redact(child);
    }
    return output;
  }
  return value;
}

const data = JSON.parse(fs.readFileSync(source, 'utf8'));
fs.writeFileSync(target, JSON.stringify(redact(data), null, 2) + '\n');
NODE
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

remove_toml_table_in_place() {
    local file="$1"
    local table="$2"
    local tmp_file
    tmp_file="$(mktemp)"

    awk -v table="$table" '
        /^[[:space:]]*\[/ {
            skip = ($0 == table)
            if (skip) {
                removed = 1
                next
            }
        }
        skip { next }
        { print }
        END {
            if (removed) {
                exit 2
            }
        }
    ' "$file" > "$tmp_file" || {
        local status=$?
        if [[ $status -ne 2 ]]; then
            rm -f "$tmp_file"
            return "$status"
        fi
    }

    mv "$tmp_file" "$file"
}

remove_codex_unsupported_startup_mcp_in_place() {
    local file="$1"
    local table

    for table in "${CODEX_DISABLED_STARTUP_MCP_TABLES[@]}"; do
        remove_toml_table_in_place "$file" "$table"
    done
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
    remove_codex_unsupported_startup_mcp_in_place "$tmp_file"
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

install_codex_memory_link() {
    if [[ ! -f "$CODEX_MEMORY_SOURCE" ]]; then
        log_error "Codex 长期记忆源文件不存在: $CODEX_MEMORY_SOURCE"
        exit 1
    fi

    mkdir -p "$(dirname "$CODEX_MEMORY_RUNTIME")"

    if [[ -e "$CODEX_MEMORY_RUNTIME" && ! -L "$CODEX_MEMORY_RUNTIME" ]]; then
        backup_file "$CODEX_MEMORY_RUNTIME" "Codex 长期记忆"
        rm -f "$CODEX_MEMORY_RUNTIME"
    fi

    ln -sfn "$CODEX_MEMORY_SOURCE" "$CODEX_MEMORY_RUNTIME"
    log_success "Codex 长期记忆已链接: $CODEX_MEMORY_RUNTIME -> $CODEX_MEMORY_SOURCE"
}

install_codex_heartbeat_timer() {
    local service_source="$CODEX_SYSTEMD_SOURCE_DIR/codex-heartbeat.service"
    local timer_source="$CODEX_SYSTEMD_SOURCE_DIR/codex-heartbeat.timer"

    if [[ ! -f "$service_source" || ! -f "$timer_source" ]]; then
        log_error "Codex heartbeat systemd 模板不存在: $CODEX_SYSTEMD_SOURCE_DIR"
        exit 1
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        log_warn "未找到 systemctl，跳过 heartbeat timer 安装"
        return 0
    fi

    mkdir -p "$CODEX_SYSTEMD_RUNTIME_DIR"
    ln -sfn "$service_source" "$CODEX_SYSTEMD_RUNTIME_DIR/codex-heartbeat.service"
    ln -sfn "$timer_source" "$CODEX_SYSTEMD_RUNTIME_DIR/codex-heartbeat.timer"

    if ! systemctl --user daemon-reload; then
        log_warn "systemd user daemon-reload 失败，已写入 timer 文件但未启用"
        return 0
    fi

    if systemctl --user enable --now codex-heartbeat.timer; then
        log_success "Codex heartbeat timer 已启用: codex-heartbeat.timer"
    else
        log_warn "Codex heartbeat timer 启用失败，可稍后手动运行: systemctl --user enable --now codex-heartbeat.timer"
    fi
}

cmd_codex_backup_runtime() {
    log_info "开始备份 Codex 可复用配置到: $CODEX_RUNTIME_BACKUP_DIR"

    if [[ ! -d "$CODEX_RUNTIME_DIR" ]]; then
        log_error "Codex 运行时目录不存在: $CODEX_RUNTIME_DIR"
        exit 1
    fi

    mkdir -p "$CODEX_RUNTIME_BACKUP_DIR"

    local file
    for file in AGENTS.md config.toml hooks.json hooks.json.omx-native-hooks.bak version.json; do
        if [[ -f "$CODEX_RUNTIME_DIR/$file" ]]; then
            cp "$CODEX_RUNTIME_DIR/$file" "$CODEX_RUNTIME_BACKUP_DIR/$file"
            log_success "已备份 Codex 文件: $file"
        fi
    done

    local dir
    for dir in agents prompts rules skills; do
        if [[ -d "$CODEX_RUNTIME_DIR/$dir" ]]; then
            rsync -a --delete "$CODEX_RUNTIME_DIR/$dir/" "$CODEX_RUNTIME_BACKUP_DIR/$dir/"
            log_success "已备份 Codex 目录: $dir"
        fi
    done

    if [[ -d "$CODEX_RUNTIME_DIR/memories" ]]; then
        rsync -aL --delete "$CODEX_RUNTIME_DIR/memories/" "$CODEX_RUNTIME_BACKUP_DIR/memories/"
        log_success "已备份 Codex 目录: memories"
    fi

    if [[ -f "$CODEX_RUNTIME_BACKUP_DIR/rules/default.rules" ]]; then
        sed -i '/claude\.com\/cai\/oauth\/authorize/d' "$CODEX_RUNTIME_BACKUP_DIR/rules/default.rules"
        log_success "已清理过期 OAuth 授权 URL 规则: rules/default.rules"
    fi

    {
        echo "# Codex Runtime Backup"
        echo
        echo "Generated: $(date -Is)"
        echo "Source: $CODEX_RUNTIME_DIR"
        echo "Target: $CODEX_RUNTIME_BACKUP_DIR"
        echo
        echo "## Included"
        echo
        echo "- AGENTS.md"
        echo "- config.toml"
        echo "- hooks.json"
        echo "- hooks.json.omx-native-hooks.bak, if present"
        echo "- version.json"
        echo "- agents/"
        echo "- prompts/"
        echo "- rules/"
        echo "- memories/ (symlinks dereferenced)"
        echo "- skills/ (runtime symlinks preserved)"
        echo
        echo "## Excluded"
        echo
        echo "- auth.json"
        echo "- history.jsonl"
        echo "- log/ and logs_*.sqlite*"
        echo "- sessions/"
        echo "- shell_snapshots/"
        echo "- state_*.sqlite*"
        echo "- cache/, tmp/, .tmp/"
        echo "- expired OAuth authorize URL allow-rules in rules/default.rules"
        echo
        echo "These excluded files are runtime state or likely to contain secrets, tokens,"
        echo "conversation history, or high-churn local telemetry."
    } > "$CODEX_RUNTIME_BACKUP_DIR/README.md"

    find "$CODEX_RUNTIME_BACKUP_DIR" -maxdepth 2 -mindepth 1 -printf '%M %s %p -> %l\n' \
        | sort > "$CODEX_RUNTIME_BACKUP_DIR/inventory.txt"

    log_success "Codex 可复用配置备份完成"
}

cmd_codex_backup_all() {
    cmd_codex_backup_runtime
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
        copy_claude_json_sanitized "$CLAUDE_RUNTIME" "$CLAUDE_SOURCE"
        copy_claude_json_sanitized "$CLAUDE_CONFIG_RUNTIME" "$CLAUDE_CONFIG_SOURCE"
        copy_claude_json_sanitized "$CLAUDE_GLOBAL_RUNTIME" "$CLAUDE_GLOBAL_SOURCE"
        log_success "Claude Code 配置已备份: $CLAUDE_SOURCE"
        log_info "Claude Code 敏感字段已写成占位符"
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

cmd_codex_autonomy() {
    cmd_codex_full_auto
    install_codex_memory_link
    install_codex_heartbeat_timer
    "$PROJECT_DIR/scripts/codex_heartbeat.py" --quiet || log_warn "首次 heartbeat 生成失败，可稍后运行: cheartbeat"

    log_success "Codex 自主管理配置已安装"
    log_info "长期记忆: $CODEX_MEMORY_RUNTIME"
    log_info "heartbeat: $PROJECT_DIR/docs/agent-memory/heartbeat.md"
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

    if [[ -f "$PROJECT_DIR/scripts/codex_heartbeat.py" ]]; then
        if python3 -m py_compile "$PROJECT_DIR/scripts/codex_heartbeat.py"; then
            log_success "Codex heartbeat 脚本语法正确"
        else
            log_error "Codex heartbeat 脚本语法错误"
            has_error=1
        fi
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
    echo "  codex-backup-runtime  备份 ~/.codex 可复用配置到 configs/codex/runtime"
    echo "  codex-backup-all      codex-backup-runtime 的兼容别名"
    echo "  codex-full-auto  安装 Codex 全自动默认入口到模板和运行时"
    echo "  codex-autonomy   安装 Codex 全自动入口、长期记忆和 heartbeat timer"
    echo "  validate         验证配置格式"
    echo "  help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 codex-backup-runtime"
    echo "  $0 codex-full-auto"
    echo "  $0 codex-autonomy"
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
    codex-backup-runtime)
        cmd_codex_backup_runtime
        ;;
    codex-backup-all)
        cmd_codex_backup_all
        ;;
    codex-full-auto)
        cmd_codex_full_auto
        ;;
    codex-autonomy)
        cmd_codex_autonomy
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
