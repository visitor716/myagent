#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
UNIT_SOURCE="$PROJECT_ROOT/configs/codex/systemd/codex-app-server-watchdog.service"
RUNTIME_DIR="${CODEX_WATCHDOG_RUNTIME_DIR:-$HOME/.local/libexec/codex-app-server-watchdog}"
SYSTEMD_USER_DIR="${CODEX_SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
UNIT_TARGET="$SYSTEMD_USER_DIR/codex-app-server-watchdog.service"
INSTALL_ONLY="${CODEX_WATCHDOG_INSTALL_ONLY:-0}"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

install_runtime_file() {
    local source="$1"
    local target="$2"
    local mode="$3"
    local label="$4"
    local target_dir tmp_file backup_file

    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir"
    tmp_file="$(mktemp "$target.tmp.XXXXXX")"
    install -m "$mode" "$source" "$tmp_file"

    if [[ -e "$target" || -L "$target" ]]; then
        if cmp -s "$tmp_file" "$target"; then
            rm -f "$tmp_file"
            printf '[INFO] %s 无需更新: %s\n' "$label" "$target"
            return 0
        fi

        backup_file="$target.backup.$BACKUP_STAMP"
        cp -L "$target" "$backup_file"
        chmod "$mode" "$backup_file"
        printf '[INFO] 已备份 %s: %s\n' "$label" "$backup_file"
    fi

    mv -Tf "$tmp_file" "$target"
    printf '[OK] %s 已安装: %s\n' "$label" "$target"
}

for source_file in \
    "$SCRIPT_DIR/codex_app_server_watchdog.sh" \
    "$SCRIPT_DIR/codex_app_server_watchdog_lib.sh" \
    "$UNIT_SOURCE"
do
    if [[ ! -f "$source_file" ]]; then
        printf '[ERROR] 缺少 watchdog 安装源文件: %s\n' "$source_file" >&2
        exit 1
    fi
done

install_runtime_file \
    "$SCRIPT_DIR/codex_app_server_watchdog.sh" \
    "$RUNTIME_DIR/codex_app_server_watchdog.sh" \
    755 \
    "Codex app-server watchdog"
install_runtime_file \
    "$SCRIPT_DIR/codex_app_server_watchdog_lib.sh" \
    "$RUNTIME_DIR/codex_app_server_watchdog_lib.sh" \
    644 \
    "Codex app-server watchdog library"
install_runtime_file \
    "$UNIT_SOURCE" \
    "$UNIT_TARGET" \
    644 \
    "Codex app-server watchdog unit"

if [[ "$INSTALL_ONLY" == "1" ]]; then
    printf '[OK] Codex app-server watchdog 运行时文件已完成离线安装\n'
    exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
    printf '[ERROR] 未找到 systemctl，无法启用 Codex app-server watchdog\n' >&2
    exit 1
fi

systemctl --user daemon-reload
systemctl --user reenable codex-app-server-watchdog.service
systemctl --user restart codex-app-server-watchdog.service
systemctl --user is-active --quiet codex-app-server-watchdog.service

printf '[OK] Codex app-server watchdog 已启用并运行\n'
