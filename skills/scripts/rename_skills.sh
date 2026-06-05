#!/bin/bash
# 批量重命名本地 skill 脚本
# 给每个 skill 添加 "my-" 前缀

set -euo pipefail

SKILLS_LOCAL_DIR="/home/zhanxp/projects/myagent/skills/skills-local"
CLAUDE_SKILLS_DIR="/home/zhanxp/.claude/skills"
CODEX_SKILLS_DIR="/home/zhanxp/.codex/skills"
HERMES_SKILLS_DIR="/home/zhanxp/.hermes/skills/myagent"
AGENTS_SKILLS_DIR="/home/zhanxp/.agents/skills"

DRY_RUN=0
VERBOSE=0

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        log "$*"
    fi
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

批量重命名本地 skill，添加 "my-" 前缀

Options:
    --dry-run    只显示将要执行的操作，不实际执行
    --verbose    显示详细输出
    -h, --help   显示帮助信息
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log "未知选项: $1"
            usage
            ;;
    esac
done

# 获取所有非符号链接的 skill 目录
get_local_skills() {
    local dir="$1"
    local skills=()
    for d in "$dir"/*; do
        if [ -d "$d" ] && [ ! -L "$d" ]; then
            local basename=$(basename "$d")
            if [ "$basename" != "codex-launchers" ]; then
                skills+=("$basename")
            fi
        fi
    done
    echo "${skills[@]}"
}

# 更新 SKILL.md 文件
update_skill_md() {
    local skill_dir="$1"
    local old_name="$2"
    local new_name="$3"

    local skill_md="$skill_dir/SKILL.md"
    if [ ! -f "$skill_md" ]; then
        verbose "SKILL.md 不存在: $skill_md"
        return 0
    fi

    # 更新 frontmatter 中的 name 字段
    # 匹配格式: name: old-name
    if grep -q "^name: $old_name" "$skill_md"; then
        verbose "更新 SKILL.md name 字段: $old_name -> $new_name"
        if [ "$DRY_RUN" -eq 0 ]; then
            sed -i "s/^name: $old_name/name: $new_name/" "$skill_md"
        fi
    elif grep -q "^name: " "$skill_md"; then
        # 如果 name 字段存在但值不同，也尝试更新
        local current_name=$(grep "^name: " "$skill_md" | head -1 | sed 's/^name: //')
        verbose "更新 SKILL.md name 字段: $current_name -> $new_name"
        if [ "$DRY_RUN" -eq 0 ]; then
            sed -i "s/^name: $current_name/name: $new_name/" "$skill_md"
        fi
    fi
}

# 更新 .skill-source.json 文件
update_skill_source_json() {
    local skill_dir="$1"
    local old_name="$2"
    local new_name="$3"

    local json_file="$skill_dir/.skill-source.json"
    if [ ! -f "$json_file" ]; then
        verbose ".skill-source.json 不存在: $json_file"
        return 0
    fi

    verbose "更新 .skill-source.json: $old_name -> $new_name"

    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi

    # 使用 Python 进行安全的 JSON 操作
    python3 - <<END
import json
import os

json_file = "$json_file"
old_name = "$old_name"
new_name = "$new_name"

with open(json_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

# 更新 name 字段
if 'name' in data:
    data['name'] = new_name

# 更新 source_of_truth 路径
if 'source_of_truth' in data:
    data['source_of_truth'] = data['source_of_truth'].replace(
        '/' + old_name, '/' + new_name)

# 更新 runtime_targets
if 'runtime_targets' in data:
    new_targets = []
    for target in data['runtime_targets']:
        new_targets.append(target.replace('/' + old_name, '/' + new_name))
    data['runtime_targets'] = new_targets

with open(json_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
END
}

# 在目录中创建 usage-stats.json
create_usage_stats() {
    local skill_dir="$1"
    local skill_name="$2"

    local stats_file="$skill_dir/usage-stats.json"
    if [ -f "$stats_file" ]; then
        verbose "usage-stats.json 已存在: $stats_file"
        return 0
    fi

    verbose "创建 usage-stats.json: $skill_name"

    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi

    cat >"$stats_file" <<END
{
  "name": "$skill_name",
  "total_calls": 0,
  "first_used": null,
  "last_used": null,
  "calls_by_date": {}
}
END
}

# 更新符号链接
update_symlinks() {
    local old_name="$1"
    local new_name="$2"
    local target_dir="$3"

    if [ ! -d "$target_dir" ]; then
        verbose "目录不存在，跳过: $target_dir"
        return 0
    fi

    local old_link="$target_dir/$old_name"
    local new_link="$target_dir/$new_name"

    # 检查旧链接
    if [ -L "$old_link" ]; then
        local old_target=$(readlink "$old_link")
        verbose "旧符号链接: $old_link -> $old_target"

        # 创建新链接
        local new_target=$(echo "$old_target" | sed "s/$old_name\$/$new_name/")
        log "创建新符号链接: $new_link -> $new_target"
        if [ "$DRY_RUN" -eq 0 ]; then
            ln -sf "$new_target" "$new_link"

            # 保留旧链接作为兼容别名，指向新目录
            log "创建兼容链接: $old_link -> $new_target"
            ln -sf "$new_target" "$old_link"
        fi
    elif [ -d "$old_link" ] && [ ! -L "$old_link" ]; then
        # 如果旧位置是真实目录而不是链接，谨慎处理
        log "警告: $old_link 是真实目录，不是符号链接，跳过"
    else
        verbose "旧链接不存在: $old_link"
    fi
}

# 重命名单个 skill
rename_skill() {
    local old_name="$1"
    local new_name="my-$old_name"

    local old_dir="$SKILLS_LOCAL_DIR/$old_name"
    local new_dir="$SKILLS_LOCAL_DIR/$new_name"

    if [ ! -d "$old_dir" ]; then
        log "目录不存在，跳过: $old_dir"
        return 0
    fi

    if [ -d "$new_dir" ]; then
        log "目标目录已存在，跳过: $new_dir"
        return 0
    fi

    log "========================================"
    log "处理 skill: $old_name -> $new_name"
    log "========================================"

    # 1. 先更新文件内容（在重命名目录之前）
    update_skill_md "$old_dir" "$old_name" "$new_name"
    update_skill_source_json "$old_dir" "$old_name" "$new_name"
    create_usage_stats "$old_dir" "$new_name"

    # 2. 重命名目录
    log "重命名目录: $old_dir -> $new_dir"
    if [ "$DRY_RUN" -eq 0 ]; then
        mv "$old_dir" "$new_dir"
    fi

    # 3. 更新符号链接
    update_symlinks "$old_name" "$new_name" "$CLAUDE_SKILLS_DIR"
    update_symlinks "$old_name" "$new_name" "$CODEX_SKILLS_DIR"
    update_symlinks "$old_name" "$new_name" "$HERMES_SKILLS_DIR"
    update_symlinks "$old_name" "$new_name" "$AGENTS_SKILLS_DIR"

    log "完成: $old_name -> $new_name"
    echo
}

# 主函数
main() {
    log "开始批量重命名本地 skills"
    log "源目录: $SKILLS_LOCAL_DIR"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN 模式：不会实际执行任何修改"
    fi

    local skills=($(get_local_skills "$SKILLS_LOCAL_DIR"))

    log "找到 ${#skills[@]} 个本地 skill"

    for skill in "${skills[@]}"; do
        rename_skill "$skill"
    done

    log "========================================"
    log "所有操作完成！"
    log "========================================"
}

main
