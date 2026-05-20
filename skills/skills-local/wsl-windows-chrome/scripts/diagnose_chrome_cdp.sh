#!/usr/bin/env bash
# 诊断 Windows Chrome CDP 连接状态
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"

usage() {
  cat <<'USAGE'
Usage: diagnose_chrome_cdp.sh [options]

Diagnose Windows Chrome CDP connectivity from WSL.

Options:
  --browser <chrome|edge>  Select the Windows browser family
  --port <port>            Override the Windows CDP port (default: 9222)
  --user-data-dir <path>   Override the Windows automation user-data-dir
  --help                   Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --browser)
      BROWSER="$2"
      shift 2
      ;;
    --port)
      CDP_PORT="$2"
      shift 2
      ;;
    --user-data-dir)
      WINDOWS_USER_DATA_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

BROWSER="$(wsl_windows_chrome_normalize_browser "$BROWSER")"
BROWSER_LABEL="$(wsl_windows_chrome_browser_label "$BROWSER")"
WINDOWS_USER_DATA_DIR_RESOLVED="$(wsl_windows_chrome_user_data_dir "$BROWSER" "$WINDOWS_USER_DATA_DIR")"
WINDOWS_GATEWAY="$(wsl_windows_chrome_gateway)"

echo "=== WSL Windows Chrome CDP 诊断 ==="
echo ""
echo "配置:"
echo "  浏览器: $BROWSER_LABEL"
echo "  CDP 端口: $CDP_PORT"
echo "  用户数据目录: $WINDOWS_USER_DATA_DIR_RESOLVED"
echo "  Windows 网关 IP: $WINDOWS_GATEWAY"
echo ""

# 检查 1: python3 是否可用
echo "检查 1: Python3 可用性"
if wsl_windows_chrome_has_cmd python3; then
  echo "  ✓ python3 已安装"
else
  echo "  ✗ python3 未安装"
  echo ""
  echo "诊断结果: CDP unreachable (缺少 python3)"
  exit 1
fi

# 检查 2: powershell.exe 是否可用
echo "检查 2: PowerShell 可用性"
if wsl_windows_chrome_has_powershell; then
  echo "  ✓ powershell.exe 可用"
else
  echo "  ✗ powershell.exe 不可用"
  echo ""
  echo "诊断结果: CDP unreachable (缺少 PowerShell)"
  exit 1
fi

# 检查 3: 本地 127.0.0.1 连接
echo "检查 3: 127.0.0.1:$CDP_PORT 连接"
local_ok=false
if wsl_windows_chrome_endpoint_reachable "127.0.0.1" "$CDP_PORT"; then
  echo "  ✓ TCP 端口可达"
  if wsl_windows_chrome_http_json_version "127.0.0.1" "$CDP_PORT" >/dev/null 2>&1; then
    echo "  ✓ /json/version 端点响应"
    local_ok=true
  else
    echo "  ✗ /json/version 端点无响应"
  fi
else
  echo "  ✗ TCP 端口不可达"
fi

# 检查 4: Windows 网关连接
echo "检查 4: $WINDOWS_GATEWAY:$CDP_PORT 连接"
gateway_ok=false
if [[ -n "$WINDOWS_GATEWAY" ]]; then
  if wsl_windows_chrome_endpoint_reachable "$WINDOWS_GATEWAY" "$CDP_PORT"; then
    echo "  ✓ TCP 端口可达"
    if wsl_windows_chrome_http_json_version "$WINDOWS_GATEWAY" "$CDP_PORT" >/dev/null 2>&1; then
      echo "  ✓ /json/version 端点响应"
      gateway_ok=true
    else
      echo "  ✗ /json/version 端点无响应"
    fi
  else
    echo "  ✗ TCP 端口不可达"
  fi
else
  echo "  ⚠  无法获取 Windows 网关 IP"
fi

# 检查 5: 从 DevToolsActivePort 或进程获取端口
echo "检查 5: 从浏览器配置/进程发现端口"
discovered_port=""
active_port_path=""
mapfile -t devtools_lines < <(wsl_windows_chrome_read_profile_port "$BROWSER" "$WINDOWS_USER_DATA_DIR" | sed '/^$/d')
if [[ "${#devtools_lines[@]}" -ge 4 ]]; then
  active_port_path="${devtools_lines[2]}"
  discovered_port="${devtools_lines[3]}"
  echo "  ✓ 发现浏览器进程，使用端口: $discovered_port"
  echo "    ActivePort 路径: $active_port_path"

  if [[ "$discovered_port" != "$CDP_PORT" ]]; then
    echo "    ⚠  发现的端口 ($discovered_port) 与请求的端口 ($CDP_PORT) 不同"
  fi
else
  echo "  ✗ 未发现浏览器配置或进程"
fi

echo ""
echo "=== 诊断结果 ==="
echo ""

if [[ "$local_ok" == true || "$gateway_ok" == true ]]; then
  echo "✓ CDP reachable"
  echo ""
  if [[ "$local_ok" == true ]]; then
    echo "可以使用 localhost 端点: http://127.0.0.1:$CDP_PORT/json/version"
  elif [[ "$gateway_ok" == true ]]; then
    echo "可以使用 Windows 网关端点: http://$WINDOWS_GATEWAY:$CDP_PORT/json/version"
  fi

  # 尝试获取 WebSocket 端点
  if [[ "$local_ok" == true ]]; then
    if ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "127.0.0.1" "$CDP_PORT" 2>/dev/null)"; then
      echo "WebSocket 端点: $ws_endpoint"
    fi
  elif [[ "$gateway_ok" == true ]]; then
    if ws_endpoint="$(wsl_windows_chrome_http_ws_endpoint "$WINDOWS_GATEWAY" "$CDP_PORT" 2>/dev/null)"; then
      echo "WebSocket 端点: $ws_endpoint"
    fi
  fi
  exit 0
else
  echo "✗ CDP unreachable"
  echo ""
  echo "--- 解决方案 ---"
  echo ""
  echo "请在 Windows PowerShell 中运行以下命令启动浏览器："
  echo ""

  # 输出启动命令 - 使用简单的 printf
  printf '$chrome = "$env:ProgramFiles\\Google\\Chrome\\Application\\chrome.exe"\n'
  printf 'if (!(Test-Path $chrome)) {\n'
  printf '  $chrome = "${env:ProgramFiles(x86)}\\Google\\Chrome\\Application\\chrome.exe"\n'
  printf '}\n'
  printf 'if (!(Test-Path $chrome)) {\n'
  printf '  throw "Chrome not found"\n'
  printf '}\n'
  printf 'Start-Process $chrome -ArgumentList @(\n'
  printf '  "--remote-debugging-address=0.0.0.0",\n'
  printf '  "--remote-debugging-port=%s",\n' "$CDP_PORT"
  printf '  "--user-data-dir=\"%s\""\n' "$WINDOWS_USER_DATA_DIR_RESOLVED"
  printf ')\n'

  echo ""
  echo "--- 验证命令 ---"
  echo ""
  echo "启动浏览器后，在 Windows PowerShell 中运行："
  printf '  Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:%s/json/version"\n' "$CDP_PORT"
  echo ""
  echo "或在 WSL 中运行："
  printf '  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "'
  printf 'try { (Invoke-WebRequest -UseBasicParsing \"http://127.0.0.1:%s/json/version\").Content; exit 0 } ' "$CDP_PORT"
  printf 'catch { Write-Host $_.Exception.Message; exit 1 }"'
  echo ""
  echo ""
  echo "然后重新运行诊断脚本验证："
  printf '  bash "%s/diagnose_chrome_cdp.sh" --browser "%s" --port "%s" --user-data-dir "%s"\n' "$SCRIPT_DIR" "$BROWSER" "$CDP_PORT" "$WINDOWS_USER_DATA_DIR_RESOLVED"
  exit 1
fi
