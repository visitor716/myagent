param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "recover", "watch", "install-task", "uninstall-task", "task-status")]
    [string]$Action,

    [int]$IntervalSeconds = 60,
    [int]$ConsecutiveFailures = 2,
    [int]$MaxRecoveries = 3,
    [int]$MaxChecks = 0,

    [string]$TaskName = "MyAgent-aTrust-VPN-Keeper",
    [switch]$DryRun,
    [switch]$ForceRestart
)

$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "MyAgent\aTrustVpnKeeper"
$LogPath = Join-Path $AppDir "keeper.log"
$InstalledScriptPath = Join-Path $AppDir "atrust_vpn_keeper.ps1"
$StartupFilePath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)) "$TaskName.cmd"
$RunRegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunRegistryValueName = $TaskName

function Ensure-AppDir {
    if (-not (Test-Path $AppDir)) {
        New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Output $line
    try {
        Ensure-AppDir
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch {
        Write-Verbose "log write failed: $($_.Exception.Message)"
    }
}

function Invoke-Or-DryRun {
    param([string]$Description, [scriptblock]$Script)
    if ($DryRun) {
        Write-Log "[dry-run] $Description"
        return
    }
    Write-Log $Description
    & $Script
}

function Get-RunRegistryCommand {
    try {
        $item = Get-ItemProperty -Path $RunRegistryPath -Name $RunRegistryValueName -ErrorAction Stop
        return $item.$RunRegistryValueName
    } catch {
        return $null
    }
}

function Set-RunRegistryFallback {
    param([string]$Command)
    New-Item -Path $RunRegistryPath -Force | Out-Null
    New-ItemProperty -Path $RunRegistryPath -Name $RunRegistryValueName -Value $Command -PropertyType String -Force | Out-Null
    Write-Log "created HKCU Run fallback: $RunRegistryPath\$RunRegistryValueName"
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

function Get-AtrustInstallInfo {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Sangfor\aTrust",
        "HKLM:\SOFTWARE\Sangfor\aTrust",
        "HKCU:\Software\Sangfor\aTrust"
    )

    $installRoots = New-Object System.Collections.Generic.List[string]
    foreach ($path in $registryPaths) {
        foreach ($name in @("InstallLocation", "InstallPath", "Path")) {
            $value = Get-RegistryValue -Path $path -Name $name
            if ($value -and -not $installRoots.Contains([string]$value)) {
                $installRoots.Add([string]$value)
            }
        }
    }
    $fallbackRoot = "C:\Program Files (x86)\Sangfor\aTrust"
    if (-not $installRoots.Contains($fallbackRoot)) {
        $installRoots.Add($fallbackRoot)
    }

    foreach ($root in $installRoots) {
        if (-not $root) {
            continue
        }
        $root = $root.TrimEnd("\")
        $candidates = @(
            (Join-Path $root "aTrustTray\aTrustTray.exe"),
            (Join-Path $root "aTrustTray.exe")
        )
        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                return [pscustomobject]@{
                    InstallRoot = $root
                    TrayPath = $candidate
                    ServiceName = "aTrustService"
                }
            }
        }
    }

    return [pscustomobject]@{
        InstallRoot = $fallbackRoot
        TrayPath = (Join-Path $fallbackRoot "aTrustTray\aTrustTray.exe")
        ServiceName = "aTrustService"
    }
}

function Get-AtrustProcesses {
    $names = @("aTrustTray.exe", "aTrustAgent.exe", "aTrustXtunnel.exe")
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $names -contains $_.Name } |
        Select-Object ProcessId, Name, ExecutablePath, CommandLine)
    return $processes
}

function Get-AtrustSnapshot {
    $install = Get-AtrustInstallInfo
    $service = Get-Service -Name $install.ServiceName -ErrorAction SilentlyContinue
    $processes = @(Get-AtrustProcesses)
    $tray = @($processes | Where-Object { $_.Name -eq "aTrustTray.exe" })
    $agent = @($processes | Where-Object { $_.Name -eq "aTrustAgent.exe" })
    $tunnel = @($processes | Where-Object { $_.Name -eq "aTrustXtunnel.exe" })
    $mainTray = @($tray | Where-Object { -not $_.CommandLine -or $_.CommandLine -notmatch "\s--type=" })

    $serviceRunning = $service -and $service.Status -eq "Running"
    $trayRunning = $tray.Count -gt 0
    $agentRunning = $agent.Count -gt 0
    $tunnelRunning = $tunnel.Count -gt 0
    $healthy = $serviceRunning -and $trayRunning -and $agentRunning -and $tunnelRunning

    $missing = New-Object System.Collections.Generic.List[string]
    if (-not $serviceRunning) { $missing.Add("service") }
    if (-not $trayRunning) { $missing.Add("tray") }
    if (-not $agentRunning) { $missing.Add("agent") }
    if (-not $tunnelRunning) { $missing.Add("tunnel") }

    return [pscustomobject]@{
        Healthy = [bool]$healthy
        Missing = ($missing -join ",")
        ServiceName = $install.ServiceName
        ServiceStatus = if ($service) { [string]$service.Status } else { "Missing" }
        ServiceStartType = if ($service) { [string]$service.StartType } else { "Unknown" }
        InstallRoot = $install.InstallRoot
        TrayPath = $install.TrayPath
        TrayExists = [bool](Test-Path $install.TrayPath)
        TrayCount = $tray.Count
        MainTrayCount = $mainTray.Count
        AgentCount = $agent.Count
        TunnelCount = $tunnel.Count
        ProcessIds = (($processes | Sort-Object Name, ProcessId | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ",")
    }
}

function Show-Status {
    $snapshot = Get-AtrustSnapshot
    $snapshot | Format-List
    try {
        $task = & schtasks.exe /Query /TN $TaskName /FO LIST 2>$null
        if ($LASTEXITCODE -eq 0) {
            ""
            "Scheduled task:"
            $task
        }
    } catch {
        Write-Verbose "task query failed: $($_.Exception.Message)"
    }
    if (Test-Path $StartupFilePath) {
        ""
        "Startup fallback:"
        $StartupFilePath
    }
    $runCommand = Get-RunRegistryCommand
    if ($runCommand) {
        ""
        "HKCU Run fallback:"
        "$RunRegistryPath\$RunRegistryValueName"
        $runCommand
    }
}

function Start-AtrustTray {
    param([string]$TrayPath)
    if (-not (Test-Path $TrayPath)) {
        throw "aTrustTray.exe not found: $TrayPath"
    }
    Invoke-Or-DryRun "start aTrust tray: $TrayPath" {
        Start-Process -FilePath $TrayPath | Out-Null
    }
}

function Recover-Atrust {
    $before = Get-AtrustSnapshot
    Write-Log "before recover: healthy=$($before.Healthy) missing=$($before.Missing) service=$($before.ServiceStatus) tray=$($before.TrayCount) agent=$($before.AgentCount) tunnel=$($before.TunnelCount)"

    if ($ForceRestart) {
        Invoke-Or-DryRun "force stop aTrust tray processes" {
            Get-Process -Name "aTrustTray" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    if ($before.ServiceStatus -eq "Missing") {
        Write-Log "aTrust service is missing; cannot start service"
    } elseif ($before.ServiceStatus -ne "Running") {
        Invoke-Or-DryRun "start service $($before.ServiceName)" {
            Start-Service -Name $before.ServiceName -ErrorAction Stop
        }
        Start-Sleep -Seconds 3
    }

    $current = Get-AtrustSnapshot
    if (-not $current.TrayExists) {
        Write-Log "aTrust tray executable is missing: $($current.TrayPath)"
    } elseif (-not $current.TrayCount -or -not $current.TunnelCount) {
        Start-AtrustTray -TrayPath $current.TrayPath
        Start-Sleep -Seconds 10
    }

    $after = Get-AtrustSnapshot
    Write-Log "after recover: healthy=$($after.Healthy) missing=$($after.Missing) service=$($after.ServiceStatus) tray=$($after.TrayCount) agent=$($after.AgentCount) tunnel=$($after.TunnelCount)"
    if (-not $after.Healthy -and -not $after.TunnelCount) {
        Write-Log "tunnel is still absent; saved login, MFA, or service-side session policy may require manual login"
    }
    return $after
}

function Watch-Atrust {
    if ($IntervalSeconds -lt 10) {
        throw "IntervalSeconds must be at least 10."
    }
    if ($ConsecutiveFailures -lt 1) {
        throw "ConsecutiveFailures must be at least 1."
    }

    Write-Log "watch started interval=${IntervalSeconds}s consecutiveFailures=$ConsecutiveFailures maxRecoveries=$MaxRecoveries maxChecks=$MaxChecks dryRun=$DryRun"
    $failureCount = 0
    $recoveries = 0
    $checks = 0
    while ($true) {
        $checks += 1
        $snapshot = Get-AtrustSnapshot
        if ($snapshot.Healthy) {
            if ($failureCount -gt 0) {
                Write-Log "health restored without recovery"
            }
            $failureCount = 0
            Write-Log "healthy service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount)"
        } else {
            $failureCount += 1
            Write-Log "unhealthy[$failureCount/$ConsecutiveFailures] missing=$($snapshot.Missing) service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount)"
            if ($failureCount -ge $ConsecutiveFailures) {
                Recover-Atrust | Out-Null
                $recoveries += 1
                $failureCount = 0
                if ($MaxRecoveries -gt 0 -and $recoveries -ge $MaxRecoveries) {
                    Write-Log "watch stopped after MaxRecoveries=$MaxRecoveries"
                    return
                }
            }
        }
        if ($MaxChecks -gt 0 -and $checks -ge $MaxChecks) {
            Write-Log "watch stopped after MaxChecks=$MaxChecks"
            return
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Install-WatchTask {
    Ensure-AppDir
    if (-not $PSCommandPath) {
        throw "PSCommandPath is unavailable; run this script from a file."
    }
    Invoke-Or-DryRun "copy helper to $InstalledScriptPath" {
        Copy-Item -Path $PSCommandPath -Destination $InstalledScriptPath -Force
    }

    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstalledScriptPath`" -Action watch -IntervalSeconds $IntervalSeconds -ConsecutiveFailures $ConsecutiveFailures -MaxRecoveries $MaxRecoveries"
    Invoke-Or-DryRun "create scheduled task $TaskName" {
        & schtasks.exe /Create /TN $TaskName /TR $taskCommand /SC ONLOGON /F | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Log "schtasks /Create failed with exit code $LASTEXITCODE; falling back to Startup folder"
            $startupCommand = "@echo off`r`nstart `"`" /min $taskCommand`r`n"
            try {
                Set-Content -Path $StartupFilePath -Value $startupCommand -Encoding ASCII -ErrorAction Stop
                Write-Log "created Startup fallback: $StartupFilePath"
            } catch {
                Write-Log "Startup fallback failed: $($_.Exception.Message); falling back to HKCU Run"
                Set-RunRegistryFallback -Command $taskCommand
            }
        }
    }
    Write-Log "task command: $taskCommand"
}

function Uninstall-WatchTask {
    Invoke-Or-DryRun "delete scheduled task $TaskName" {
        & schtasks.exe /Delete /TN $TaskName /F | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Log "schtasks /Delete exited $LASTEXITCODE; continuing with Startup fallback cleanup"
        }
        if (Test-Path $StartupFilePath) {
            Remove-Item -Path $StartupFilePath -Force
            Write-Log "removed Startup fallback: $StartupFilePath"
        }
        if (Get-RunRegistryCommand) {
            Remove-ItemProperty -Path $RunRegistryPath -Name $RunRegistryValueName -Force
            Write-Log "removed HKCU Run fallback: $RunRegistryPath\$RunRegistryValueName"
        }
    }
}

function Show-TaskStatus {
    & schtasks.exe /Query /TN $TaskName /FO LIST
    $runCommand = Get-RunRegistryCommand
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $StartupFilePath) -and -not $runCommand) {
        throw "scheduled task, Startup fallback, and HKCU Run fallback not found: $TaskName"
    }
    if (Test-Path $StartupFilePath) {
        ""
        "Startup fallback:"
        $StartupFilePath
    }
    if ($runCommand) {
        ""
        "HKCU Run fallback:"
        "$RunRegistryPath\$RunRegistryValueName"
        $runCommand
    }
}

switch ($Action) {
    "status" { Show-Status }
    "recover" { Recover-Atrust | Format-List }
    "watch" { Watch-Atrust }
    "install-task" {
        Install-WatchTask
        if (-not $DryRun) {
            Show-TaskStatus
        }
    }
    "uninstall-task" { Uninstall-WatchTask }
    "task-status" { Show-TaskStatus }
}
