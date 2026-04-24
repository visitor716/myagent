#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

LISTEN_PORT="${1:-${WSL_WINDOWS_CHROME_RELAY_PORT:-39222}}"
TARGET_PORT="${2:-${WSL_WINDOWS_CHROME_CDP_PORT:-9222}}"
BIND_HOST="${3:-}"

usage() {
  cat <<'USAGE'
Usage: start_windows_chrome_cdp_relay.sh [listen-port] [target-port] [bind-host]

Arguments:
  listen-port  WSL-visible relay port (default: 39222)
  target-port  Windows automation browser CDP port (default: 9222)
  bind-host    Windows host address to bind (default: WSL gateway or WSL_WINDOWS_CHROME_RELAY_BIND_HOST)
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! wsl_windows_chrome_has_cmd powershell.exe; then
  echo "powershell.exe not found; this helper requires WSL with Windows interop enabled." >&2
  exit 1
fi

if [[ -z "$BIND_HOST" ]]; then
  BIND_HOST="$(wsl_windows_chrome_relay_bind_host "$(wsl_windows_chrome_gateway)")"
fi

if [[ -z "$BIND_HOST" ]]; then
  echo "Unable to determine a relay bind host from WSL networking." >&2
  exit 1
fi

RELAY_KEY="$(wsl_windows_chrome_relay_key "$BIND_HOST" "$LISTEN_PORT" "$TARGET_PORT")"

cat <<'INFO'
Starting a Windows-local TCP relay so WSL can reach the automation browser CDP port.
This helper writes a small Node relay into %USERPROFILE%\.codex\wsl-windows-chrome and launches it hidden.
INFO

PS_SCRIPT=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$listenPort = __LISTEN_PORT__
$targetPort = __TARGET_PORT__
$bindHost = '__BIND_HOST__'
$relayRoot = Join-Path $env:USERPROFILE '.codex\wsl-windows-chrome'
$relayPath = Join-Path $relayRoot 'chrome_cdp_proxy___RELAY_KEY__.js'
$js = @"
const net = require('net');
const listenPort = Number(process.argv[2]);
const targetPort = Number(process.argv[3]);
const bindHost = process.argv[4];

const server = net.createServer((client) => {
  const target = net.connect({ host: '127.0.0.1', port: targetPort }, () => {
    client.pipe(target);
    target.pipe(client);
  });
  target.on('error', () => client.destroy());
  client.on('error', () => target.destroy());
});

server.on('error', (error) => {
  console.error(error.message || String(error));
  process.exit(1);
});

server.listen(listenPort, bindHost);
"@

New-Item -ItemType Directory -Force -Path $relayRoot | Out-Null
Set-Content -Path $relayPath -Value $js -Encoding UTF8

Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -match '^node(.exe)?$' -and
    $_.CommandLine -like "*$relayRoot*" -and
    $_.CommandLine -like "* $listenPort *" -and
    $_.CommandLine -like "* $bindHost*"
  } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Process -WindowStyle Hidden -FilePath 'node' -ArgumentList @($relayPath, $listenPort, $targetPort, $bindHost) | Out-Null
PS1
)

PS_SCRIPT="${PS_SCRIPT//__LISTEN_PORT__/$LISTEN_PORT}"
PS_SCRIPT="${PS_SCRIPT//__TARGET_PORT__/$TARGET_PORT}"
PS_SCRIPT="${PS_SCRIPT//__BIND_HOST__/$(wsl_windows_chrome_escape_ps_single_quote "$BIND_HOST")}"
PS_SCRIPT="${PS_SCRIPT//__RELAY_KEY__/$RELAY_KEY}"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$PS_SCRIPT" >/dev/null

if ! wsl_windows_chrome_wait_for_endpoint "$BIND_HOST" "$LISTEN_PORT" 5 0.2; then
  echo "Relay did not become reachable on $BIND_HOST:$LISTEN_PORT." >&2
  exit 1
fi

echo "Connect browser CDP via: http://$BIND_HOST:$LISTEN_PORT/json/version"
