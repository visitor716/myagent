[CmdletBinding()]
param(
    [ValidateSet('watch', 'collect-once', 'install-startup', 'uninstall-startup', 'status', 'stop')]
    [string]$Action = 'watch',
    [int]$IntervalSeconds = 30,
    [int]$EventLookbackMinutes = 10,
    [int]$MaxSnapshots = 240,
    [string]$LogRoot = "$env:USERPROFILE\Desktop\network-power-monitor"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'MyAgent\NetworkPowerMonitor'
$installedScript = Join-Path $installDir 'network-power-monitor.ps1'
$startupCmd = Join-Path ([Environment]::GetFolderPath('Startup')) 'MyAgent-NetworkPowerMonitor.cmd'

function New-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Quote-CmdArgument {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-WatchProcesses {
    $escaped = [regex]::Escape('network-power-monitor.ps1')
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -match $escaped -and
            $_.CommandLine -match '-Action\s+watch'
        }
}

function Start-WatchProcess {
    param(
        [string]$ScriptPath,
        [int]$Seconds,
        [string]$Root
    )

    $running = @(Get-WatchProcesses)
    if ($running.Count -gt 0) {
        Write-Host "Monitor already running: $($running.ProcessId -join ', ')"
        return
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', (Quote-CmdArgument $ScriptPath),
        '-Action', 'watch',
        '-IntervalSeconds', $Seconds,
        '-EventLookbackMinutes', $EventLookbackMinutes,
        '-MaxSnapshots', $MaxSnapshots,
        '-LogRoot', (Quote-CmdArgument $Root)
    )

    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    Write-Host "Monitor started. LogRoot=$Root"
}

function Install-Startup {
    New-Directory $installDir
    if ($PSCommandPath -and ($PSCommandPath -ne $installedScript)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    }

    $content = @"
@echo off
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$installedScript" -Action watch -IntervalSeconds $IntervalSeconds -EventLookbackMinutes $EventLookbackMinutes -MaxSnapshots $MaxSnapshots -LogRoot "$LogRoot"
"@
    Set-Content -LiteralPath $startupCmd -Value $content -Encoding ASCII
    Write-Host "Startup launcher installed: $startupCmd"
    Start-WatchProcess -ScriptPath $installedScript -Seconds $IntervalSeconds -Root $LogRoot
}

function Uninstall-Startup {
    if (Test-Path -LiteralPath $startupCmd) {
        Remove-Item -LiteralPath $startupCmd -Force
        Write-Host "Removed startup launcher: $startupCmd"
    }
    else {
        Write-Host "Startup launcher not found: $startupCmd"
    }
}

function Stop-WatchProcess {
    $processes = @(Get-WatchProcesses)
    if ($processes.Count -eq 0) {
        Write-Host 'No running monitor process found.'
        return
    }

    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force
        Write-Host "Stopped monitor process: $($process.ProcessId)"
    }
}

function Show-Status {
    Write-Host "LogRoot: $LogRoot"
    Write-Host "StartupLauncher: $startupCmd"
    Write-Host ("StartupInstalled: {0}" -f (Test-Path -LiteralPath $startupCmd))
    if (Test-Path -LiteralPath $startupCmd) {
        Write-Host 'StartupLauncherContent:'
        Get-Content -LiteralPath $startupCmd | ForEach-Object { Write-Host "  $_" }
    }

    $processes = @(Get-WatchProcesses)
    if ($processes.Count -eq 0) {
        Write-Host 'Running: false'
    }
    else {
        Write-Host 'Running: true'
        $processes |
            Select-Object ProcessId, Name, CommandLine |
            Format-List
    }

    $heartbeat = Join-Path $LogRoot 'heartbeat.csv'
    $latest = Join-Path $LogRoot 'latest.txt'
    if (Test-Path -LiteralPath $heartbeat) {
        Write-Host "Heartbeat: $heartbeat"
        Get-Content -LiteralPath $heartbeat -Tail 5
    }
    if (Test-Path -LiteralPath $latest) {
        Write-Host "LatestSnapshot: $latest"
        Get-Item -LiteralPath $latest | Select-Object FullName, Length, LastWriteTime | Format-List
    }
}

function Invoke-TextCommand {
    param(
        [string]$Path,
        [string]$Title,
        [scriptblock]$Script
    )

    Add-Content -LiteralPath $Path -Value ''
    Add-Content -LiteralPath $Path -Value "===== $Title ====="
    try {
        $output = & $Script 2>&1 | Out-String -Width 240
        if ([string]::IsNullOrWhiteSpace($output)) {
            Add-Content -LiteralPath $Path -Value '(no output)'
        }
        else {
            Add-Content -LiteralPath $Path -Value $output.TrimEnd()
        }
    }
    catch {
        Add-Content -LiteralPath $Path -Value ("ERROR: {0}" -f $_.Exception.Message)
    }
}

function Get-NetshWlanSummary {
    $summary = [ordered]@{
        WlanState = ''
        Ssid = ''
        Signal = ''
        RadioType = ''
    }

    $lines = @(netsh.exe wlan show interfaces 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^\s*(State|状态)\s*:\s*(.+?)\s*$') {
            $summary.WlanState = $Matches[2]
        }
        elseif ($line -match '^\s*SSID\s+:\s+(.+?)\s*$') {
            $summary.Ssid = $Matches[1]
        }
        elseif ($line -match '^\s*(Signal|信号)\s*:\s*(.+?)\s*$') {
            $summary.Signal = $Matches[2]
        }
        elseif ($line -match '^\s*(Radio type|无线电类型)\s*:\s*(.+?)\s*$') {
            $summary.RadioType = $Matches[2]
        }
    }

    return [pscustomobject]$summary
}

function Get-ActivePowerScheme {
    try {
        return ((& powercfg.exe /getactivescheme 2>$null) -join ' ').Trim()
    }
    catch {
        return ''
    }
}

function Get-PowerOnlineSummary {
    $status = [ordered]@{
        PowerOnline = ''
        BatteryPercent = ''
        BatteryStatus = ''
    }

    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($battery) {
            $status.BatteryPercent = $battery.EstimatedChargeRemaining
            $status.BatteryStatus = $battery.BatteryStatus
        }
    }
    catch {}

    try {
        $wmiStatus = Get-CimInstance -Namespace root/WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wmiStatus) {
            $status.PowerOnline = $wmiStatus.PowerOnline
        }
    }
    catch {}

    return [pscustomobject]$status
}

function Test-PingHost {
    param([string]$HostName)

    $null = & ping.exe -n 1 -w 1000 $HostName 2>$null
    if ($LASTEXITCODE -eq 0) {
        return 'ok'
    }
    return 'fail'
}

function Get-DefaultRouteSummary {
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1
        if (-not $route) {
            return ''
        }
        return ('if={0};nextHop={1};routeMetric={2};ifMetric={3}' -f $route.InterfaceAlias, $route.NextHop, $route.RouteMetric, $route.InterfaceMetric)
    }
    catch {
        return ''
    }
}

function Get-DnsSummary {
    try {
        $rows = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 } |
            ForEach-Object { ('{0}={1}' -f $_.InterfaceAlias, ($_.ServerAddresses -join '/')) }
        return ($rows -join '; ')
    }
    catch {
        return ''
    }
}

function Get-RelevantSystemEvents {
    param([datetime]$Since)

    $providerPattern = 'WLAN|Netwtw|Kernel-Power|Power-Troubleshooter|DNS-Client|Tcpip|NDIS|WER-SystemErrorReporting|BugCheck|volmgr|Service Control Manager|Hyper-V-VmSwitch|WUDFRd'
    $messagePattern = 'WLAN|Wi-Fi|Netwtw|network|adapter|disconnect|limited connectivity|网络|断开|驱动|0x0000009f|bugcheck|DRIVER_POWER_STATE_FAILURE|Kernel-Power|sleep|standby|Modern Standby|Lid|DNS|WUDFRd|IntelHaxm|Sdp|Vnic|VmSwitch|Hyper-V'

    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $Since } -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProviderName -match $providerPattern -or
            $_.Message -match $messagePattern
        } |
        Sort-Object TimeCreated
}

function Append-NewEvents {
    param(
        [string]$LogPath,
        [datetime]$Since
    )

    $statePath = Join-Path (Split-Path -Parent $LogPath) 'state.json'
    $lastRecordId = 0
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($state.LastSystemRecordId) {
                $lastRecordId = [int64]$state.LastSystemRecordId
            }
        }
        catch {}
    }

    $events = @(Get-RelevantSystemEvents -Since $Since | Where-Object { $_.RecordId -gt $lastRecordId })
    if ($events.Count -eq 0) {
        return
    }

    foreach ($event in $events) {
        $message = (($event.Message -replace "`r|`n", ' ') -replace '\s+', ' ').Trim()
        $line = '{0} id={1} record={2} provider={3} level={4} message={5}' -f `
            $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.fff'), `
            $event.Id, `
            $event.RecordId, `
            $event.ProviderName, `
            $event.LevelDisplayName, `
            $message
        Add-Content -LiteralPath $LogPath -Value $line
    }

    $maxRecordId = ($events | Measure-Object -Property RecordId -Maximum).Maximum
    [pscustomobject]@{
        LastSystemRecordId = [int64]$maxRecordId
        UpdatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding ASCII
}

function Write-Heartbeat {
    param(
        [string]$CsvPath,
        [pscustomobject]$Record
    )

    if (Test-Path -LiteralPath $CsvPath) {
        $Record | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $Record | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    }
}

function Prune-Snapshots {
    param(
        [string]$SnapshotDir,
        [int]$Keep
    )

    Get-ChildItem -LiteralPath $SnapshotDir -Filter '*.txt' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-Snapshot {
    New-Directory $LogRoot
    $snapshotDir = Join-Path $LogRoot 'snapshots'
    New-Directory $snapshotDir

    $now = Get-Date
    $stamp = $now.ToString('yyyyMMdd-HHmmss')
    $snapshotPath = Join-Path $snapshotDir "$stamp.txt"
    $latestPath = Join-Path $LogRoot 'latest.txt'
    $eventsPath = Join-Path $LogRoot 'events.log'
    $heartbeatPath = Join-Path $LogRoot 'heartbeat.csv'
    $since = $now.AddMinutes(-1 * $EventLookbackMinutes)

    $wlan = Get-NetshWlanSummary
    $power = Get-PowerOnlineSummary
    $activeScheme = Get-ActivePowerScheme
    $defaultRoute = Get-DefaultRouteSummary
    $dns = Get-DnsSummary
    $pingAli = Test-PingHost '223.5.5.5'
    $pingCloudflare = Test-PingHost '1.1.1.1'

    $events = @(Get-RelevantSystemEvents -Since $since)
    $eventSummary = ($events | Select-Object -Last 12 | ForEach-Object {
        $message = (($_.Message -replace "`r|`n", ' ') -replace '\s+', ' ').Trim()
        '{0} id={1} provider={2} {3}' -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $_.ProviderName, $message
    }) -join ' | '

    Set-Content -LiteralPath $snapshotPath -Value ("Network/power snapshot at {0}" -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz')) -Encoding UTF8
    Add-Content -LiteralPath $snapshotPath -Value ("LogRoot: {0}" -f $LogRoot)
    Add-Content -LiteralPath $snapshotPath -Value ("IntervalSeconds: {0}" -f $IntervalSeconds)
    Add-Content -LiteralPath $snapshotPath -Value ("ActivePowerScheme: {0}" -f $activeScheme)
    Add-Content -LiteralPath $snapshotPath -Value ("PowerOnline: {0}; BatteryPercent: {1}; BatteryStatus: {2}" -f $power.PowerOnline, $power.BatteryPercent, $power.BatteryStatus)
    Add-Content -LiteralPath $snapshotPath -Value ("WLAN: state={0}; ssid={1}; signal={2}; radio={3}" -f $wlan.WlanState, $wlan.Ssid, $wlan.Signal, $wlan.RadioType)
    Add-Content -LiteralPath $snapshotPath -Value ("DefaultRoute: {0}" -f $defaultRoute)
    Add-Content -LiteralPath $snapshotPath -Value ("DNS: {0}" -f $dns)
    Add-Content -LiteralPath $snapshotPath -Value ("Ping223.5.5.5: {0}; Ping1.1.1.1: {1}" -f $pingAli, $pingCloudflare)
    Add-Content -LiteralPath $snapshotPath -Value ("RecentRelevantEvents: {0}" -f $events.Count)
    Add-Content -LiteralPath $snapshotPath -Value ("RecentEventSummary: {0}" -f $eventSummary)

    Invoke-TextCommand $snapshotPath 'powercfg /getactivescheme' { powercfg.exe /getactivescheme }
    Invoke-TextCommand $snapshotPath 'powercfg /qh CONNECTIVITYINSTANDBY' { powercfg.exe /qh SCHEME_CURRENT SUB_NONE f15576e8-98b7-4186-b944-eafa664402d9 }
    Invoke-TextCommand $snapshotPath 'powercfg /query sleep timers' {
        powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
        powercfg.exe /query SCHEME_CURRENT SUB_SLEEP UNATTENDSLEEP
        powercfg.exe /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE
    }
    Invoke-TextCommand $snapshotPath 'battery and AC state' {
        Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object Name, BatteryStatus, EstimatedChargeRemaining, EstimatedRunTime | Format-List
        Get-CimInstance -Namespace root/WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object InstanceName, PowerOnline, Discharging, Charging, Critical | Format-List
    }
    Invoke-TextCommand $snapshotPath 'net adapters' {
        Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState, DriverVersion, DriverDate |
            Format-Table -AutoSize
    }
    Invoke-TextCommand $snapshotPath 'net ip configuration' {
        Get-NetIPConfiguration -ErrorAction SilentlyContinue | Format-List
    }
    Invoke-TextCommand $snapshotPath 'default routes' {
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') -or $_.DestinationPrefix -like '100.*' } |
            Sort-Object DestinationPrefix, RouteMetric, InterfaceMetric |
            Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric, InterfaceMetric, State |
            Format-Table -AutoSize
    }
    Invoke-TextCommand $snapshotPath 'dns client servers' {
        Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Format-Table -AutoSize
    }
    Invoke-TextCommand $snapshotPath 'wlan interfaces' { netsh.exe wlan show interfaces }
    Invoke-TextCommand $snapshotPath 'wlan drivers' { netsh.exe wlan show drivers }
    Invoke-TextCommand $snapshotPath 'windows proxy state' {
        Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue |
            Select-Object ProxyEnable, ProxyServer, AutoConfigURL, ProxyOverride |
            Format-List
        netsh.exe winhttp show proxy
    }
    Invoke-TextCommand $snapshotPath 'recent relevant system events' {
        $events |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, RecordId, @{n = 'Message'; e = { (($_.Message -replace "`r|`n", ' ') -replace '\s+', ' ').Trim() } } |
            Format-List
    }

    Copy-Item -LiteralPath $snapshotPath -Destination $latestPath -Force
    Append-NewEvents -LogPath $eventsPath -Since $since

    $record = [pscustomobject]@{
        Time = $now.ToString('o')
        ActivePowerScheme = $activeScheme
        PowerOnline = $power.PowerOnline
        BatteryPercent = $power.BatteryPercent
        WlanState = $wlan.WlanState
        Ssid = $wlan.Ssid
        Signal = $wlan.Signal
        RadioType = $wlan.RadioType
        DefaultRoute = $defaultRoute
        Dns = $dns
        Ping223_5_5_5 = $pingAli
        Ping1_1_1_1 = $pingCloudflare
        RelevantEventCount = $events.Count
        LatestSnapshot = $snapshotPath
    }
    Write-Heartbeat -CsvPath $heartbeatPath -Record $record
    Prune-Snapshots -SnapshotDir $snapshotDir -Keep $MaxSnapshots

    Write-Host "Snapshot written: $snapshotPath"
}

function Start-WatchLoop {
    New-Directory $LogRoot
    $monitorLog = Join-Path $LogRoot 'monitor.log'
    Add-Content -LiteralPath $monitorLog -Value ("[{0}] watch started interval={1}s logroot={2}" -f (Get-Date).ToString('s'), $IntervalSeconds, $LogRoot)

    while ($true) {
        try {
            Write-Snapshot | Out-Null
        }
        catch {
            Add-Content -LiteralPath $monitorLog -Value ("[{0}] ERROR {1}" -f (Get-Date).ToString('s'), $_.Exception.Message)
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

switch ($Action) {
    'install-startup' {
        Install-Startup
    }
    'uninstall-startup' {
        Uninstall-Startup
    }
    'status' {
        Show-Status
    }
    'stop' {
        Stop-WatchProcess
    }
    'collect-once' {
        Write-Snapshot
    }
    'watch' {
        Start-WatchLoop
    }
}
