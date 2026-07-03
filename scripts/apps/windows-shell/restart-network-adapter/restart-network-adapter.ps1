[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$AdapterName = 'WLAN',
    [int]$DisableWaitSeconds = 3,
    [int]$ReconnectWaitSeconds = 25,
    [string]$ProbeUrl = 'http://www.msftconnecttest.com/connecttest.txt',
    [switch]$SkipConnectivityCheck,
    [switch]$SkipDhcpDnsRefresh,
    [switch]$SkipWlanServiceRestart,
    [switch]$NoElevate,
    [switch]$PauseAfterRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

trap {
    Write-Error $_
    if ($PauseAfterRun) {
        Read-Host 'Press Enter to close'
    }
    exit 1
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-ElevatedScriptPath {
    if ($PSCommandPath -notlike '\\*') {
        return $PSCommandPath
    }

    $localDir = Join-Path $env:TEMP 'myagent-restart-network-adapter'
    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
    $localPath = Join-Path $localDir 'restart-network-adapter.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $localPath -Force
    Write-Host "Copied UNC script to local temp path for elevation: $localPath"
    return $localPath
}

function Restart-Elevated {
    $scriptPath = Get-ElevatedScriptPath
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-Argument $scriptPath),
        '-AdapterName', (Quote-Argument $AdapterName),
        '-DisableWaitSeconds', $DisableWaitSeconds,
        '-ReconnectWaitSeconds', $ReconnectWaitSeconds,
        '-ProbeUrl', (Quote-Argument $ProbeUrl)
    )

    if ($SkipConnectivityCheck) {
        $args += '-SkipConnectivityCheck'
    }
    if ($SkipDhcpDnsRefresh) {
        $args += '-SkipDhcpDnsRefresh'
    }
    if ($SkipWlanServiceRestart) {
        $args += '-SkipWlanServiceRestart'
    }
    if ($WhatIfPreference) {
        $args += '-WhatIf'
    }
    if ($PauseAfterRun) {
        $args += '-PauseAfterRun'
    }

    Write-Host "Administrator rights are required. Requesting elevation..."
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs | Out-Null
}

function Get-CurrentWlanSsid {
    $lines = @(netsh.exe wlan show interfaces 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^\s*SSID\s+:\s+(.+?)\s*$') {
            return $Matches[1]
        }
    }
    return $null
}

function Show-RecentBugcheckHint {
    $since = (Get-Date).AddHours(-2)
    $event = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
        Id = 1001
        StartTime = $since
    } -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($event -and $event.Message -match '0x0000009f') {
        Write-Warning 'Recent DRIVER_POWER_STATE_FAILURE (0x9f) bugcheck detected. This script can restart networking after Windows comes back, but it cannot fix the underlying driver/power crash.'
        Write-Warning (($event.Message -replace "`r|`n", ' ') -replace '\s+', ' ')
    }
}

function Test-ConnectivityProbe {
    param([string]$Url)

    Write-Host "Connectivity probe: $Url"
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8
        Write-Host ("Probe OK: HTTP {0}" -f [int]$response.StatusCode)
        return $true
    }
    catch {
        Write-Warning ("Probe failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Invoke-DhcpDnsRefresh {
    param([string]$Name)

    Write-Host "Refreshing DNS and DHCP for adapter '$Name'..."
    ipconfig.exe /flushdns | Out-Host
    ipconfig.exe /renew $Name | Out-Host
}

function Restart-WlanService {
    param(
        [string]$Adapter,
        [string]$Ssid
    )

    Write-Host 'Restarting WLAN AutoConfig service...'
    Restart-Service -Name WlanSvc -Force
    Start-Sleep -Seconds 5

    if ($Ssid) {
        Write-Host "Reconnecting WLAN profile '$Ssid'..."
        netsh.exe wlan connect name="$Ssid" interface="$Adapter" | Out-Host
    }
}

function Find-NetworkAdapter {
    param([string]$Name)

    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if ($adapter) {
        return $adapter
    }

    $matches = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -like "*$Name*" -or $_.Name -like "*$Name*"
    }

    if (@($matches).Count -eq 1) {
        return $matches
    }

    Write-Host "Available adapters:"
    Get-NetAdapter |
        Sort-Object Name |
        Select-Object Name, InterfaceDescription, Status, LinkSpeed |
        Format-Table -AutoSize

    if (@($matches).Count -gt 1) {
        throw "Adapter name '$Name' is ambiguous. Use the exact adapter Name."
    }

    throw "Adapter '$Name' was not found."
}

function Wait-AdapterUp {
    param(
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 1
        $current = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
        if ($current -and $current.Status -eq 'Up') {
            return $current
        }
    } while ((Get-Date) -lt $deadline)

    return Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
}

$adapter = Find-NetworkAdapter -Name $AdapterName
$currentSsid = Get-CurrentWlanSsid

Write-Host "Target adapter:"
$adapter |
    Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState |
    Format-Table -AutoSize

if ((-not $WhatIfPreference) -and (-not (Test-IsAdministrator))) {
    if ($NoElevate) {
        throw "Administrator rights are required to restart network adapters."
    }
    Restart-Elevated
    exit 0
}

Show-RecentBugcheckHint

if ($PSCmdlet.ShouldProcess($adapter.Name, 'Restart network adapter')) {
    Restart-NetAdapter -Name $adapter.Name -Confirm:$false
    if ($DisableWaitSeconds -gt 0) {
        Start-Sleep -Seconds $DisableWaitSeconds
    }
}

if ($PauseAfterRun) {
    Read-Host 'Press Enter to close'
}

$current = Wait-AdapterUp -Name $adapter.Name -TimeoutSeconds $ReconnectWaitSeconds

Write-Host "Adapter after restart:"
$current |
    Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState |
    Format-Table -AutoSize

if (Get-Command netsh.exe -ErrorAction SilentlyContinue) {
    Write-Host "Current WLAN interface:"
    netsh.exe wlan show interfaces
}

if (-not $SkipConnectivityCheck) {
    $probeOk = Test-ConnectivityProbe -Url $ProbeUrl

    if ((-not $probeOk) -and (-not $SkipDhcpDnsRefresh)) {
        Invoke-DhcpDnsRefresh -Name $adapter.Name
        Start-Sleep -Seconds 3
        $probeOk = Test-ConnectivityProbe -Url $ProbeUrl
    }

    if ((-not $probeOk) -and (-not $SkipWlanServiceRestart)) {
        Restart-WlanService -Adapter $adapter.Name -Ssid $currentSsid
        $current = Wait-AdapterUp -Name $adapter.Name -TimeoutSeconds $ReconnectWaitSeconds
        Write-Host "Adapter after WLAN service restart:"
        $current |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState |
            Format-Table -AutoSize
        $probeOk = Test-ConnectivityProbe -Url $ProbeUrl
    }

    if (-not $probeOk) {
        Write-Warning "The adapter may still be connected to Wi-Fi while DNS, gateway, captive portal, driver power state, or internet access is unavailable."
    }
}
