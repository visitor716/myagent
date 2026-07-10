Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PollSeconds = 5
$DebounceSeconds = 15
$WslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
$LogDirectory = Join-Path $env:LOCALAPPDATA 'MyAgent\CodexProxy'
$LogFile = Join-Path $LogDirectory 'watch-clash-proxy.log'
$WslCommand = 'source "$HOME/.wsl-proxy.env"; proxyon && proxycheck'

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
    Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message"
}

function Get-ClashProcessIds {
    @(Get-Process -Name 'clash-verge', 'verge-mihomo' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id)
}

function Invoke-WslProxyCheck {
    Write-Log 'Running proxyon && proxycheck after Clash startup'

    $output = & $WslExe -d Ubuntu -u zhanxp -- bash -c $WslCommand 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        $text = [string]$line
        if ($text -notmatch '^(?i:set-cookie|report-to|nel):') {
            Add-Content -LiteralPath $LogFile -Value $text
        }
    }

    if ($exitCode -eq 0) {
        Write-Log 'proxyon && proxycheck succeeded'
    } else {
        Write-Log "proxyon && proxycheck failed with exit code $exitCode"
    }
}

$knownProcessIds = [System.Collections.Generic.HashSet[int]]::new()
foreach ($processId in (Get-ClashProcessIds)) {
    [void]$knownProcessIds.Add([int]$processId)
}

$lastRun = [datetime]::MinValue
Write-Log "Started Clash proxy watcher; known process count=$($knownProcessIds.Count)"

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    $currentProcessIds = [System.Collections.Generic.HashSet[int]]::new()
    $newProcessDetected = $false
    foreach ($processId in (Get-ClashProcessIds)) {
        $id = [int]$processId
        [void]$currentProcessIds.Add($id)
        if (-not $knownProcessIds.Contains($id)) {
            $newProcessDetected = $true
        }
    }

    $knownProcessIds = $currentProcessIds
    if (-not $newProcessDetected) {
        continue
    }

    if (((Get-Date) - $lastRun).TotalSeconds -lt $DebounceSeconds) {
        Write-Log 'Skipped duplicate Clash process start within debounce window'
        continue
    }

    Start-Sleep -Seconds 3
    $lastRun = Get-Date
    Invoke-WslProxyCheck
}
