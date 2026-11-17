#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_fixture() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
    cat > "$target" <<'EOF'
model = "fixture-model"

[features]
apps = true
enable_mcp_apps = true
memories = true

[mcp_servers.chrome-devtools]
type = "stdio"
command = "cmd"
args = ["/c", "npx", "chrome-devtools-mcp@latest"]

[mcp_servers.context7]
type = "stdio"
command = "cmd"
args = ["/c", "npx", "-y", "@upstash/context7-mcp"]

[mcp_servers.keep-me]
type = "stdio"
command = "keep-command"
EOF
}

WSL_CONFIG="$TMP_DIR/wsl/config.toml"
WINDOWS_CONFIG="$TMP_DIR/windows/config.toml"
SOURCE_CONFIG="$TMP_DIR/source/config.toml"
BACKUP_CONFIG="$TMP_DIR/runtime/config.toml"

for config in "$WSL_CONFIG" "$WINDOWS_CONFIG" "$SOURCE_CONFIG" "$BACKUP_CONFIG"; do
    write_fixture "$config"
done

if CODEX_RUNTIME="$WSL_CONFIG" \
    CODEX_WINDOWS_RUNTIME="$WINDOWS_CONFIG" \
    CODEX_SOURCE="$SOURCE_CONFIG" \
    CODEX_RUNTIME_BACKUP_DIR="$(dirname "$BACKUP_CONFIG")" \
    bash "$ROOT_DIR/configs/sync.sh" validate >/dev/null 2>&1; then
    echo "validate should reject forbidden startup MCP config" >&2
    exit 1
fi

CODEX_RUNTIME="$WSL_CONFIG" \
CODEX_WINDOWS_RUNTIME="$WINDOWS_CONFIG" \
bash "$ROOT_DIR/configs/sync.sh" codex-mcp-guard >/dev/null

for config in "$WSL_CONFIG" "$WINDOWS_CONFIG"; do
    ! grep -Fq '[mcp_servers.chrome-devtools]' "$config"
    ! grep -Fq '[mcp_servers.context7]' "$config"
    grep -Fxq 'apps = false' "$config"
    grep -Fxq 'enable_mcp_apps = false' "$config"
    grep -Fxq '[mcp_servers.keep-me]' "$config"
    grep -Fxq 'command = "keep-command"' "$config"
    grep -Fxq 'model = "fixture-model"' "$config"
done

sanitize_fixture() {
    local config="$1"
    CODEX_RUNTIME="$config" \
    CODEX_WINDOWS_RUNTIME="$config" \
    bash "$ROOT_DIR/configs/sync.sh" codex-mcp-guard >/dev/null
}

sanitize_fixture "$SOURCE_CONFIG"
sanitize_fixture "$BACKUP_CONFIG"

CODEX_RUNTIME="$WSL_CONFIG" \
CODEX_WINDOWS_RUNTIME="$WINDOWS_CONFIG" \
CODEX_SOURCE="$SOURCE_CONFIG" \
CODEX_RUNTIME_BACKUP_DIR="$(dirname "$BACKUP_CONFIG")" \
bash "$ROOT_DIR/configs/sync.sh" validate >/dev/null

echo "test_sync_mcp_guard: PASS"
