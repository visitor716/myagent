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

if ! wsl_windows_chrome_has_powershell; then
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

# Check if relay is already reachable
if wsl_windows_chrome_endpoint_reachable "$BIND_HOST" "$LISTEN_PORT"; then
  echo "Relay already active on $BIND_HOST:$LISTEN_PORT"
  echo "Connect browser CDP via: http://$BIND_HOST:$LISTEN_PORT/json/version"
  exit 0
fi

cat <<'INFO'
Starting a Windows-local TCP relay so WSL can reach the automation browser CDP port.
This helper writes a small PowerShell relay into %USERPROFILE%\.codex\wsl-windows-chrome and launches it hidden.
INFO

PS_SCRIPT=$(cat <<'PS1'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$listenPort = __LISTEN_PORT__
$targetPort = __TARGET_PORT__
$bindHost = '__BIND_HOST__'
$relayRoot = Join-Path $env:USERPROFILE '.codex\wsl-windows-chrome'
$relayPath = Join-Path $relayRoot 'chrome_cdp_proxy___RELAY_KEY__.ps1'
$relayScript = @'
param(
  [int]$ListenPort,
  [int]$TargetPort,
  [string]$BindHost
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public static class WslWindowsChromeTcpRelay
{
    public static void Run(int listenPort, int targetPort, string bindHost)
    {
        var listener = new TcpListener(IPAddress.Parse(bindHost), listenPort);
        listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        listener.Start();

        while (true)
        {
            var client = listener.AcceptTcpClient();
            Task.Run(() => HandleClient(client, targetPort));
        }
    }

    private static void HandleClient(TcpClient client, int targetPort)
    {
        TcpClient target = null;
        try
        {
            target = new TcpClient("127.0.0.1", targetPort);
            using (client)
            using (target)
            {
                var clientStream = client.GetStream();
                var targetStream = target.GetStream();
                var clientToTarget = clientStream.CopyToAsync(targetStream);
                var targetToClient = targetStream.CopyToAsync(clientStream);
                Task.WaitAny(clientToTarget, targetToClient);
            }
        }
        catch
        {
            try { if (target != null) target.Dispose(); } catch {}
            try { if (client != null) client.Dispose(); } catch {}
        }
    }
}
"@

[WslWindowsChromeTcpRelay]::Run($ListenPort, $TargetPort, $BindHost)
'@

New-Item -ItemType Directory -Force -Path $relayRoot | Out-Null
Set-Content -Path $relayPath -Value $relayScript -Encoding UTF8

Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -match '^(node|powershell|pwsh)(.exe)?$' -and
    $_.CommandLine -like "*$relayRoot*" -and
    $_.CommandLine -like "* $listenPort *" -and
    $_.CommandLine -like "* $bindHost*"
  } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$powershellExe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path $powershellExe)) {
  $powershellExe = 'powershell.exe'
}

Start-Process -WindowStyle Hidden -FilePath $powershellExe -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  $relayPath,
  $listenPort,
  $targetPort,
  $bindHost
) | Out-Null
PS1
)

PS_SCRIPT="${PS_SCRIPT//__LISTEN_PORT__/$LISTEN_PORT}"
PS_SCRIPT="${PS_SCRIPT//__TARGET_PORT__/$TARGET_PORT}"
PS_SCRIPT="${PS_SCRIPT//__BIND_HOST__/$(wsl_windows_chrome_escape_ps_single_quote "$BIND_HOST")}"
PS_SCRIPT="${PS_SCRIPT//__RELAY_KEY__/$RELAY_KEY}"

tmp_ps1=$(mktemp /tmp/wsl_windows_chrome_XXXXXX.ps1)
trap 'rm -f "$tmp_ps1"' EXIT
echo "$PS_SCRIPT" >"$tmp_ps1"
wsl_windows_chrome_powershell -File "$(wslpath -w "$tmp_ps1")" >/dev/null
rm -f "$tmp_ps1"

if ! wsl_windows_chrome_wait_for_endpoint "$BIND_HOST" "$LISTEN_PORT" 5 0.2; then
  echo "Relay did not become reachable on $BIND_HOST:$LISTEN_PORT." >&2
  exit 1
fi

echo "Connect browser CDP via: http://$BIND_HOST:$LISTEN_PORT/json/version"
