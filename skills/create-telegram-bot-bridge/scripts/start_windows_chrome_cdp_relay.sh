#!/usr/bin/env bash
set -euo pipefail

LISTEN_PORT="${1:-39222}"
TARGET_PORT="${2:-9222}"

cat <<'INFO'
Starting a Windows-local TCP relay so WSL can reach Chrome DevTools.
This helper writes a small Node relay to the Windows user profile and launches it hidden.
INFO

POWERSHELL_SCRIPT=$(cat <<'PS1'
$listenPort = [int]$args[0]
$targetPort = [int]$args[1]
$relayPath = Join-Path $env:USERPROFILE 'chrome_cdp_proxy.js'
$js = @"
const net = require('net');
const LISTEN_PORT = parseInt(process.argv[2], 10);
const TARGET_PORT = parseInt(process.argv[3], 10);
const server = net.createServer((socket) => {
  const upstream = net.connect({ host: '127.0.0.1', port: TARGET_PORT });
  socket.pipe(upstream);
  upstream.pipe(socket);
  const closeBoth = () => {
    socket.destroy();
    upstream.destroy();
  };
  socket.on('error', closeBoth);
  upstream.on('error', closeBoth);
});
server.listen(LISTEN_PORT, '0.0.0.0');
"@

Set-Content -Path $relayPath -Value $js -Encoding UTF8

Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match 'node' -and $_.CommandLine -like "*$relayPath*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$node = @(
  (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
  'D:\DevTools\node-v22.12.0\node.exe'
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $node) {
  throw 'node.exe not found on Windows'
}

Start-Process -FilePath $node -ArgumentList @($relayPath, $listenPort, $targetPort) -WindowStyle Hidden
PS1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$POWERSHELL_SCRIPT" -- "$LISTEN_PORT" "$TARGET_PORT"

WINDOWS_GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
echo "WSL-visible Windows gateway: $WINDOWS_GATEWAY"
echo "Relay port: $LISTEN_PORT"
echo "Connect browser CDP via: ws://$WINDOWS_GATEWAY:$LISTEN_PORT<browser-path-from-DevToolsActivePort>"
