#!/usr/bin/env bash
# 将 WSL 的本地 CDP socket 转发到已有的 Windows Chrome 中继。
set -euo pipefail

windows_gateway="$(ip -4 route show default | awk '
  $1 == "default" && $3 != "" { if (gateway == "") gateway = $3 }
  END { print gateway }
')"
if [[ -z "$windows_gateway" ]]; then
  echo '无法确定 Windows 网关，未启动 CDP 转发。' >&2
  exit 1
fi

exec /usr/lib/systemd/systemd-socket-proxyd "${windows_gateway}:39222"
