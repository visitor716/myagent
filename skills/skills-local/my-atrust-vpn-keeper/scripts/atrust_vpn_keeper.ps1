param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "login-state", "login", "recover", "watch", "install-task", "uninstall-task", "task-status", "save-credential", "clear-credential", "credential-status")]
    [string]$Action,

    [int]$IntervalSeconds = 60,
    [int]$ConsecutiveFailures = 2,
    [int]$MaxRecoveries = 3,
    [int]$MaxChecks = 0,
    [int]$ReloginCooldownSeconds = 60,
    [int]$MaxReloginAttemptsPerLogout = 3,
    [int]$UnknownLoginStateThreshold = 3,

    [string]$Username = "",
    [string]$TaskName = "MyAgent-aTrust-VPN-Keeper",
    [ValidateSet("DpiClick", "ClipboardPaste", "SendKeys")]
    [string]$InputMethod = "DpiClick",
    [int]$PostLoginWaitSeconds = 8,
    [switch]$PasswordFromStdin,
    [switch]$PromptForPassword,
    [switch]$NoSubmit,
    [switch]$AutoLogin,
    [switch]$ProbeLoginState,
    [switch]$RestartClientOnExit,
    [switch]$ForegroundProbe,
    [switch]$DryRun,
    [switch]$ForceRestart,
    [switch]$ForceLogin
)

$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "MyAgent\aTrustVpnKeeper"
$LogPath = Join-Path $AppDir "keeper.log"
$InstalledScriptPath = Join-Path $AppDir "atrust_vpn_keeper.ps1"
$RunnerCmdPath = Join-Path $AppDir "watch.cmd"
$CredentialPath = Join-Path $AppDir "credential.json"
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

function Escape-SendKeysText {
    param([string]$Text)
    if ($null -eq $Text) {
        return ""
    }
    return ($Text -replace "([\+\^%~\(\)\{\}\[\]])", '{$1}')
}

function ConvertTo-PlainText {
    param([securestring]$Secure)
    if (-not $Secure) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function ConvertFrom-PlainText {
    param([string]$Text)
    if ($null -eq $Text) {
        return $null
    }
    return (ConvertTo-SecureString -String $Text -AsPlainText -Force)
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

function Remove-RunRegistryFallbackIfPresent {
    if (Get-RunRegistryCommand) {
        Remove-ItemProperty -Path $RunRegistryPath -Name $RunRegistryValueName -Force
        Write-Log "removed stale HKCU Run fallback: $RunRegistryPath\$RunRegistryValueName"
    }
}

function Remove-StartupFallbackIfPresent {
    if (Test-Path $StartupFilePath) {
        Remove-Item -Path $StartupFilePath -Force
        Write-Log "removed stale Startup fallback: $StartupFilePath"
    }
}

function Escape-CommandArgument {
    param([string]$Value)
    if ($null -eq $Value) {
        return ""
    }
    return ($Value -replace '"', '\"')
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
    param(
        [string]$TrayPath,
        [switch]$Silent
    )
    if (-not (Test-Path $TrayPath)) {
        throw "aTrustTray.exe not found: $TrayPath"
    }
    Invoke-Or-DryRun "start aTrust tray: $TrayPath" {
        if ($Silent) {
            $previousForeground = Get-ForegroundWindowHandle
            try {
                Start-Process -FilePath $TrayPath -WindowStyle Minimized | Out-Null
                Start-Sleep -Seconds 2
                Minimize-AtrustWindow -Reason "after silent tray start" | Out-Null
            } finally {
                Restore-ForegroundWindow -WindowHandle $previousForeground -Reason "after silent tray start"
            }
        } else {
            Start-Process -FilePath $TrayPath | Out-Null
        }
    }
}

function Add-NativeWindowType {
    Add-Type @"
	using System;
	using System.Runtime.InteropServices;
	using System.Text;
	public static class NativeWindow {
	  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
	  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
	  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
	  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
	  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
	  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
	  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
	  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
	  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
	  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
	  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
	  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
	  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
	  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
	  [StructLayout(LayoutKind.Sequential)] public struct RECT {
	    public int Left;
	    public int Top;
    public int Right;
    public int Bottom;
  }
}
"@ -ErrorAction SilentlyContinue
	    [NativeWindow]::SetProcessDPIAware() | Out-Null
}

function Get-NativeWindowText {
    param([IntPtr]$WindowHandle)

    try {
        $length = [NativeWindow]::GetWindowTextLength($WindowHandle)
        if ($length -le 0) {
            return ""
        }
        $builder = New-Object System.Text.StringBuilder ($length + 1)
        [NativeWindow]::GetWindowText($WindowHandle, $builder, $builder.Capacity) | Out-Null
        return $builder.ToString()
    } catch {
        return ""
    }
}

function Get-ForegroundWindowHandle {
    Add-NativeWindowType
    return [NativeWindow]::GetForegroundWindow()
}

function Restore-ForegroundWindow {
    param(
        [IntPtr]$WindowHandle,
        [string]$Reason = "after aTrust foreground operation"
    )

    if ($WindowHandle -eq [IntPtr]::Zero) {
        return
    }

    try {
        Start-Sleep -Milliseconds 150
        [NativeWindow]::SetForegroundWindow($WindowHandle) | Out-Null
        Write-Log "restored previous foreground window $Reason"
    } catch {
        Write-Log "previous foreground window restore failed: $($_.Exception.Message)"
    }
}

function Get-AtrustWindowProcess {
    param(
        [int]$TimeoutSeconds = 10,
        [switch]$AllowSmallWindow
    )

    Add-NativeWindowType
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $processes = @(Get-Process -Name "aTrustTray" -ErrorAction SilentlyContinue)
        $processById = @{}
        foreach ($process in $processes) {
            $processById[[int]$process.Id] = $process
        }

        $candidates = New-Object System.Collections.Generic.List[object]
        if ($processById.Count -gt 0) {
            $callback = [NativeWindow+EnumWindowsProc]{
                param([IntPtr]$hwnd, [IntPtr]$lParam)

                if (-not [NativeWindow]::IsWindowVisible($hwnd)) {
                    return $true
                }

                [uint32]$windowPid = 0
                [NativeWindow]::GetWindowThreadProcessId($hwnd, [ref]$windowPid) | Out-Null
                $windowProcessId = [int]$windowPid
                if (-not $processById.ContainsKey($windowProcessId)) {
                    return $true
                }

                try {
                    $rect = New-Object "NativeWindow+RECT"
                    if ([NativeWindow]::GetWindowRect($hwnd, [ref]$rect)) {
                        $width = [Math]::Max(0, $rect.Right - $rect.Left)
                        $height = [Math]::Max(0, $rect.Bottom - $rect.Top)
                        $area = $width * $height
                        $isSmallWindow = $area -lt 150000
                        $isMinimized = [NativeWindow]::IsIconic($hwnd)
                        if ($isSmallWindow -and -not $AllowSmallWindow) {
                            return $true
                        }

                        $title = Get-NativeWindowText -WindowHandle $hwnd
                        $rank = 2
                        if ($title -match "aTrust") {
                            $rank = 0
                        } elseif (-not [string]::IsNullOrWhiteSpace($title)) {
                            $rank = 1
                        }

                        $process = $processById[$windowProcessId]
                        $candidates.Add([pscustomobject]@{
                            Rank = $rank
                            IsMinimized = $isMinimized
                            IsSmallWindow = $isSmallWindow
                            Area = $area
                            StartTime = $process.StartTime
                            Id = $process.Id
                            MainWindowHandle = $hwnd
                            MainWindowTitle = $title
                            Process = $process
                        }) | Out-Null
                    }
                } catch {
                    return $true
                }

                return $true
            }

            [NativeWindow]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
        }

        $process = $candidates |
            Sort-Object Rank, IsMinimized, IsSmallWindow, @{ Expression = "Area"; Descending = $true }, @{ Expression = "StartTime"; Descending = $true }, Id |
            Select-Object -First 1

        if ($process) {
            return $process
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Test-ForegroundProcess {
    param([int]$ProcessId)

    Add-NativeWindowType
    $foregroundHwnd = [NativeWindow]::GetForegroundWindow()
    if ($foregroundHwnd -eq [IntPtr]::Zero) {
        return $false
    }

    [uint32]$foregroundPid = 0
    [NativeWindow]::GetWindowThreadProcessId($foregroundHwnd, [ref]$foregroundPid) | Out-Null
    return ([int]$foregroundPid -eq $ProcessId)
}

function Show-AtrustWindow {
    Add-NativeWindowType
    $process = Get-AtrustWindowProcess -TimeoutSeconds 10

    if (-not $process) {
        Write-Log "aTrust foreground failed: no visible aTrustTray window"
        return $false
    }

    if ($DryRun) {
        Write-Log "[dry-run] foreground aTrust window pid=$($process.Id) title=$($process.MainWindowTitle)"
        return $true
    }

    [NativeWindow]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
    for ($i = 0; $i -lt 5; $i += 1) {
        Start-Sleep -Milliseconds 300
        [NativeWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
        if (Test-ForegroundProcess -ProcessId $process.Id) {
            Write-Log "foreground aTrust window pid=$($process.Id)"
            return $true
        }
    }

    Write-Log "aTrust foreground failed: active window does not belong to aTrustTray pid=$($process.Id)"
    return $false
}

function Minimize-AtrustWindow {
    param([string]$Reason = "after silent operation")

    Add-NativeWindowType
    $process = Get-AtrustWindowProcess -TimeoutSeconds 2
    if (-not $process) {
        return $false
    }

    if ($DryRun) {
        Write-Log "[dry-run] minimize aTrust window $Reason pid=$($process.Id) title=$($process.MainWindowTitle)"
        return $true
    }

    [NativeWindow]::ShowWindow($process.MainWindowHandle, 6) | Out-Null
    Write-Log "minimized aTrust window $Reason pid=$($process.Id)"
    return $true
}

function Move-AtrustWindowForDpiClick {
    Add-NativeWindowType
    $process = Get-AtrustWindowProcess -TimeoutSeconds 10
    if (-not $process) {
        throw "visible aTrust window was not found"
    }

    [NativeWindow]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
    $hwndTopMost = [IntPtr](-1)
    $hwndNoTopMost = [IntPtr](-2)
    [NativeWindow]::SetWindowPos($process.MainWindowHandle, $hwndTopMost, 0, 0, 1366, 768, 0x0040) | Out-Null
    Start-Sleep -Milliseconds 120
    [NativeWindow]::SetWindowPos($process.MainWindowHandle, $hwndNoTopMost, 0, 0, 1366, 768, 0x0040) | Out-Null
    Start-Sleep -Milliseconds 500
    [NativeWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 300
    return $process
}

function Click-At {
    param([int]$X, [int]$Y)
    Add-NativeWindowType
    [NativeWindow]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 80
    [NativeWindow]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [NativeWindow]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 180
}

function Confirm-AtrustLogoutPromptIfPresent {
    # aTrust timeout/logout confirmation is an Electron modal. Its controls are
    # not exposed through useful UIAutomation, so send harmless center-dialog
    # confirmation clicks before filling the login form.
    try {
        Click-At -X 735 -Y 452
        Start-Sleep -Milliseconds 350
        Click-At -X 790 -Y 452
        Start-Sleep -Milliseconds 650
        Write-Log "sent possible aTrust logout confirmation clicks before login input"
    } catch {
        Write-Log "possible aTrust logout confirmation click failed: $($_.Exception.Message)"
    }
}

function New-AtrustWindowBitmap {
    param(
        [object]$Process,
        [switch]$AllowRestoreMinimized
    )

    Add-NativeWindowType
    Add-Type -AssemblyName System.Drawing

    if (-not $Process -or $Process.MainWindowHandle -eq 0) {
        return $null
    }

        $hwnd = $Process.MainWindowHandle
        try {
            if ([NativeWindow]::IsIconic($hwnd)) {
                if (-not $AllowRestoreMinimized) {
                    Write-Log "window capture skipped: aTrust window is minimized" | Out-Null
                    return $null
                }
                [NativeWindow]::ShowWindow($hwnd, 4) | Out-Null
                Start-Sleep -Milliseconds 300
            }

        $rect = New-Object "NativeWindow+RECT"
        if (-not [NativeWindow]::GetWindowRect($hwnd, [ref]$rect)) {
            Write-Log "window capture failed: GetWindowRect returned false" | Out-Null
            return $null
        }

        $width = [Math]::Max(0, $rect.Right - $rect.Left)
        $height = [Math]::Max(0, $rect.Bottom - $rect.Top)
        if ($width -lt 100 -or $height -lt 100) {
            Write-Log "window capture failed: invalid window size ${width}x${height}" | Out-Null
            return $null
        }

        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $hdc = $graphics.GetHdc()
        $captured = $false
        try {
            $captured = [NativeWindow]::PrintWindow($hwnd, $hdc, 2)
            if (-not $captured) {
                $captured = [NativeWindow]::PrintWindow($hwnd, $hdc, 0)
            }
        } finally {
            $graphics.ReleaseHdc($hdc)
            $graphics.Dispose()
        }

        if (-not $captured) {
            $bitmap.Dispose()
            Write-Log "window capture failed: PrintWindow returned false" | Out-Null
            return $null
        }

        return $bitmap
    } catch {
        Write-Log "window capture failed: $($_.Exception.Message)" | Out-Null
        return $null
    }
}

function Measure-BitmapColorRatio {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [ValidateSet("LoginBlue", "LoggedInGreen")]
        [string]$Kind
    )

    $matches = 0
    $total = 0
    $maxX = [Math]::Min($X + $Width, $Bitmap.Width)
    $maxY = [Math]::Min($Y + $Height, $Bitmap.Height)
    for ($py = $Y; $py -lt $maxY; $py += 4) {
        for ($px = $X; $px -lt $maxX; $px += 4) {
            $color = $Bitmap.GetPixel($px, $py)
            $hit = $false
            if ($Kind -eq "LoginBlue") {
                $hit = ($color.R -lt 90 -and $color.G -gt 80 -and $color.G -lt 170 -and $color.B -gt 180)
            } elseif ($Kind -eq "LoggedInGreen") {
                $hit = ($color.G -gt 130 -and $color.R -lt 130 -and $color.B -lt 190)
            }
            if ($hit) {
                $matches += 1
            }
            $total += 1
        }
    }

    if ($total -eq 0) {
        return 0.0
    }
    return [double]($matches / $total)
}

function Get-AtrustLoginState {
    param([switch]$Foreground)

    $snapshot = Get-AtrustSnapshot
    if (-not $snapshot.TrayExists) {
        Write-Log "login-state probe skipped: aTrust tray executable is missing"
        return [pscustomobject]@{
            State = "Unknown"
            Reason = "TrayMissing"
            CaptureSource = "None"
            LoginBlueRatio = 0.0
            LoggedInGreenRatio = 0.0
        }
    }

    if (-not $snapshot.TrayCount) {
        if (-not $Foreground) {
            Write-Log "login-state probe skipped: aTrust tray is not running in silent mode"
            return [pscustomobject]@{
                State = "Unknown"
                Reason = "TrayNotRunning"
                CaptureSource = "WindowCapture"
                LoginBlueRatio = 0.0
                LoggedInGreenRatio = 0.0
            }
        }
        Start-AtrustTray -TrayPath $snapshot.TrayPath
        Start-Sleep -Seconds 3
    }

    if (-not (Get-AtrustWindowProcess -TimeoutSeconds 2 -AllowSmallWindow)) {
        if (-not $Foreground) {
            Write-Log "login-state probe skipped: visible aTrust window is unavailable in silent mode"
            return [pscustomobject]@{
                State = "Unknown"
                Reason = "WindowUnavailableSilent"
                CaptureSource = "WindowCapture"
                LoginBlueRatio = 0.0
                LoggedInGreenRatio = 0.0
            }
        }
        Start-AtrustTray -TrayPath $snapshot.TrayPath
        Start-Sleep -Seconds 4
    }

    $bitmap = $null
    $captureSource = "WindowCapture"
    try {
        if ($Foreground) {
            try {
                Move-AtrustWindowForDpiClick | Out-Null
            } catch {
                Write-Log "login-state probe failed to show aTrust window: $($_.Exception.Message)"
                return [pscustomobject]@{
                    State = "Unknown"
                    Reason = "WindowUnavailable"
                    CaptureSource = "ForegroundScreen"
                    LoginBlueRatio = 0.0
                    LoggedInGreenRatio = 0.0
                }
            }

            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing

            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            } finally {
                $graphics.Dispose()
            }
            $captureSource = "ForegroundScreen"
        } else {
            $windowProcess = Get-AtrustWindowProcess -TimeoutSeconds 2 -AllowSmallWindow
            $bitmap = New-AtrustWindowBitmap -Process $windowProcess
            if (-not $bitmap) {
                return [pscustomobject]@{
                    State = "Unknown"
                    Reason = "WindowCaptureUnavailable"
                    CaptureSource = "WindowCapture"
                    LoginBlueRatio = 0.0
                    LoggedInGreenRatio = 0.0
                }
            }
        }

        $loginBlueRatio = Measure-BitmapColorRatio -Bitmap $bitmap -X 790 -Y 495 -Width 520 -Height 80 -Kind LoginBlue
        $loginBlueWideRatio = Measure-BitmapColorRatio -Bitmap $bitmap -X 0 -Y 0 -Width $bitmap.Width -Height $bitmap.Height -Kind LoginBlue
        $loggedInGreenRatio = Measure-BitmapColorRatio -Bitmap $bitmap -X 50 -Y 58 -Width 40 -Height 45 -Kind LoggedInGreen
    } finally {
        if ($bitmap) {
            $bitmap.Dispose()
        }
    }

    $state = "Unknown"
    $reason = "ColorProbe"
    if ($loginBlueRatio -gt 0.25) {
        $state = "LoggedOut"
        $reason = "LoginButtonVisible"
    } elseif ($loginBlueWideRatio -gt 0.018) {
        $state = "LoggedOut"
        $reason = "WideLoginBlueVisible"
    } elseif ($loggedInGreenRatio -gt 0.03) {
        $state = "LoggedIn"
        $reason = "LoggedInBadgeVisible"
    }

    Write-Log ("login-state probe state={0} reason={1} source={2} loginBlue={3:N3} loginBlueWide={4:N3} loggedInGreen={5:N3}" -f $state, $reason, $captureSource, $loginBlueRatio, $loginBlueWideRatio, $loggedInGreenRatio)
    return [pscustomobject]@{
        State = $state
        Reason = $reason
        CaptureSource = $captureSource
        LoginBlueRatio = $loginBlueRatio
        LoginBlueWideRatio = $loginBlueWideRatio
        LoggedInGreenRatio = $loggedInGreenRatio
    }
}

function Show-LoginState {
    Get-AtrustLoginState -Foreground:$ForegroundProbe | Format-List
}

function Read-PlainPassword {
    if ($PasswordFromStdin) {
        return [Console]::In.ReadLine()
    }

    if ($PromptForPassword) {
        $secure = Read-Host -Prompt "aTrust password" -AsSecureString
        return (ConvertTo-PlainText -Secure $secure)
    }

    return $null
}

function Get-SavedAtrustCredential {
    if (-not (Test-Path $CredentialPath)) {
        return $null
    }

    try {
        $record = Get-Content -Path $CredentialPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $record.Username -or -not $record.Password) {
            return $null
        }

        $secure = ConvertTo-SecureString -String ([string]$record.Password)
        return [pscustomobject]@{
            Username = [string]$record.Username
            Password = (ConvertTo-PlainText -Secure $secure)
            UpdatedAt = [string]$record.UpdatedAt
        }
    } catch {
        Write-Log "saved credential could not be read or decrypted: $($_.Exception.Message)" | Out-Null
        return $null
    }
}

function Save-AtrustCredential {
    $plainPassword = Read-PlainPassword
    if (-not $Username) {
        throw "Username is required when saving aTrust credential."
    }
    if (-not $plainPassword) {
        throw "PasswordFromStdin or PromptForPassword is required when saving aTrust credential."
    }

    Ensure-AppDir
    try {
        $secure = ConvertFrom-PlainText -Text $plainPassword
        $record = [pscustomobject]@{
            Username = $Username
            Password = (ConvertFrom-SecureString -SecureString $secure)
            Protection = "Windows DPAPI CurrentUser"
            UpdatedAt = (Get-Date).ToString("o")
        }
        $record | ConvertTo-Json | Set-Content -Path $CredentialPath -Encoding UTF8
        Write-Log "saved aTrust credential for username=$Username using Windows DPAPI CurrentUser"
        Show-CredentialStatus
    } finally {
        $plainPassword = $null
    }
}

function Clear-AtrustCredential {
    if (Test-Path $CredentialPath) {
        Remove-Item -Path $CredentialPath -Force
        Write-Log "removed saved aTrust credential: $CredentialPath"
    } else {
        Write-Log "saved aTrust credential is already absent"
    }
}

function Show-CredentialStatus {
    if (-not (Test-Path $CredentialPath)) {
        [pscustomobject]@{
            Present = $false
            Path = $CredentialPath
        } | Format-List
        return
    }

    try {
        $record = Get-Content -Path $CredentialPath -Raw -Encoding UTF8 | ConvertFrom-Json
        [pscustomobject]@{
            Present = $true
            Username = [string]$record.Username
            Protection = [string]$record.Protection
            UpdatedAt = [string]$record.UpdatedAt
            Path = $CredentialPath
        } | Format-List
    } catch {
        [pscustomobject]@{
            Present = $true
            Readable = $false
            Error = $_.Exception.Message
            Path = $CredentialPath
        } | Format-List
    }
}

function Get-LoginPlainPassword {
    $plainPassword = Read-PlainPassword
    if ($plainPassword) {
        return $plainPassword
    }

    if ($AutoLogin) {
        $credential = Get-SavedAtrustCredential
        if ($credential) {
            if (-not $Username) {
                $script:Username = $credential.Username
            }
            Write-Log "loaded saved aTrust credential for username=$($credential.Username)" | Out-Null
            return $credential.Password
        }
        Write-Log "AutoLogin requested but no saved credential is available" | Out-Null
    }

    return $null
}

function Send-AtrustLoginKeys {
    param([string]$PlainPassword)

    if (-not $PlainPassword) {
        Write-Log "password not provided; aTrust window is ready for manual login"
        return
    }

    if ($DryRun) {
        Write-Log "[dry-run] would send login input to aTrust window via $InputMethod; password is not logged"
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    if ($InputMethod -eq "DpiClick") {
        if (-not (Show-AtrustWindow)) {
            Write-Log "aTrust foreground check failed before DpiClick; continuing because coordinate click will try to focus the window"
        }
        Send-AtrustLoginViaDpiClick -PlainPassword $PlainPassword
        return
    }

    if (-not (Show-AtrustWindow)) {
        throw "aTrust window could not be foregrounded immediately before login input"
    }
    Start-Sleep -Milliseconds 500
    $windowProcess = Get-AtrustWindowProcess -TimeoutSeconds 1
    if (-not $windowProcess) {
        throw "aTrust window disappeared before login input was sent"
    }
    if (-not (Test-ForegroundProcess -ProcessId $windowProcess.Id)) {
        if (-not (Show-AtrustWindow)) {
            throw "aTrust window is not foreground; refusing to send login input"
        }
        Start-Sleep -Milliseconds 300
        $windowProcess = Get-AtrustWindowProcess -TimeoutSeconds 1
        if (-not $windowProcess -or -not (Test-ForegroundProcess -ProcessId $windowProcess.Id)) {
            throw "aTrust window is not foreground after retry; refusing to send login input"
        }
    }

    if ($InputMethod -eq "ClipboardPaste") {
        Send-AtrustLoginViaClipboard -PlainPassword $PlainPassword
        return
    }

    Send-AtrustLoginViaKeys -PlainPassword $PlainPassword
}

function Send-AtrustLoginViaKeys {
    param([string]$PlainPassword)

    if ($Username) {
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        [System.Windows.Forms.SendKeys]::SendWait((Escape-SendKeysText $Username))
        [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
        Start-Sleep -Milliseconds 200
    }

    [System.Windows.Forms.SendKeys]::SendWait((Escape-SendKeysText $PlainPassword))
    if (-not $NoSubmit) {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    }
    Write-Log "sent aTrust login input via SendKeys; password was not logged or stored"
}

function Send-AtrustClipboardText {
    param([string]$Text)

    [System.Windows.Forms.Clipboard]::SetText($Text)
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait("^v")
}

function Send-AtrustLoginViaClipboard {
    param([string]$PlainPassword)

    $savedClipboard = $null
    $hasSavedClipboard = $false
    try {
        $savedClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
        $hasSavedClipboard = ($null -ne $savedClipboard)
    } catch {
        Write-Log "clipboard snapshot failed; continuing without logging password"
    }

    try {
        if ($Username) {
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Send-AtrustClipboardText -Text $Username
            [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
            Start-Sleep -Milliseconds 200
        }

        Send-AtrustClipboardText -Text $PlainPassword
        if (-not $NoSubmit) {
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        }
        Write-Log "sent aTrust login input via ClipboardPaste; password was not logged or stored"
    } finally {
        try {
            if ($hasSavedClipboard) {
                [System.Windows.Forms.Clipboard]::SetDataObject($savedClipboard, $true)
            } else {
                [System.Windows.Forms.Clipboard]::Clear()
            }
        } catch {
            Write-Log "clipboard restore failed; clipboard may have been left with temporary login text"
        }
    }
}

function Send-AtrustLoginViaDpiClick {
    param([string]$PlainPassword)

    $savedClipboard = $null
    $hasSavedClipboard = $false
    try {
        $savedClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
        $hasSavedClipboard = ($null -ne $savedClipboard)
    } catch {
        Write-Log "clipboard snapshot failed; continuing without logging password"
    }

    try {
        Move-AtrustWindowForDpiClick | Out-Null
        Confirm-AtrustLogoutPromptIfPresent

        if ($Username) {
            Click-At -X 910 -Y 292
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Send-AtrustClipboardText -Text $Username
        }

        Click-At -X 910 -Y 386
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        Send-AtrustClipboardText -Text $PlainPassword

        if (-not $NoSubmit) {
            Click-At -X 1060 -Y 536
        }
        Write-Log "sent aTrust login input via DpiClick; password was not logged or stored"
    } finally {
        try {
            if ($hasSavedClipboard) {
                [System.Windows.Forms.Clipboard]::SetDataObject($savedClipboard, $true)
            } else {
                [System.Windows.Forms.Clipboard]::Clear()
            }
        } catch {
            Write-Log "clipboard restore failed; clipboard may have been left with temporary login text"
        }
    }
}

function Login-Atrust {
    param([switch]$WatchMode)

    if ($PostLoginWaitSeconds -lt 0) {
        throw "PostLoginWaitSeconds must be zero or greater."
    }

    $previousForeground = Get-ForegroundWindowHandle
    $before = Get-AtrustSnapshot
    Write-Log "before login: healthy=$($before.Healthy) missing=$($before.Missing) service=$($before.ServiceStatus) tray=$($before.TrayCount) agent=$($before.AgentCount) tunnel=$($before.TunnelCount)"

    if ($WatchMode -and -not $ForceLogin) {
        $watchLoginState = Get-AtrustLoginState | Select-Object -Last 1
        if ($watchLoginState.State -ne "LoggedOut") {
            Write-Log "watch login input skipped: background login-state=$($watchLoginState.State) reason=$($watchLoginState.Reason); not foregrounding aTrust without confirmed LoggedOut"
            return $before
        }
        Write-Log "watch login input allowed after background confirmed LoggedOut"
    } elseif ($before.Healthy -and -not $ForceLogin) {
        $currentLoginState = Get-AtrustLoginState | Select-Object -Last 1
        if ($currentLoginState.State -eq "LoggedIn") {
            Write-Log "aTrust is already logged in; login skipped without foregrounding"
            return $before
        }
        if (-not $AutoLogin) {
            Write-Log "aTrust is already healthy; login skipped without foregrounding"
            return $before
        }
        if ($currentLoginState.State -ne "LoggedOut") {
            Write-Log "AutoLogin requested but background login-state=$($currentLoginState.State) reason=$($currentLoginState.Reason); not foregrounding aTrust without confirmed LoggedOut"
            return $before
        }
        Write-Log "AutoLogin requested after background confirmed LoggedOut; continuing login attempt"
    }

    Recover-Atrust | Out-Null
    $afterRecover = Get-AtrustSnapshot
    if (-not $afterRecover.TrayExists) {
        throw "aTrust tray executable is missing: $($afterRecover.TrayPath)"
    }

    Start-AtrustTray -TrayPath $afterRecover.TrayPath
    Start-Sleep -Seconds 3
    $shown = Show-AtrustWindow
    if (-not $shown -and $InputMethod -eq "DpiClick") {
        Write-Log "aTrust foreground check failed before login; continuing with DpiClick fallback"
    } elseif (-not $shown) {
        throw "aTrust window could not be foregrounded; login input was not sent"
    }

    $plainPassword = Get-LoginPlainPassword
    try {
        Send-AtrustLoginKeys -PlainPassword $plainPassword
    } finally {
        $plainPassword = $null
        Restore-ForegroundWindow -WindowHandle $previousForeground -Reason "after aTrust login input"
    }

    Start-Sleep -Seconds $PostLoginWaitSeconds
    $after = Get-AtrustSnapshot
    Write-Log "after login: healthy=$($after.Healthy) missing=$($after.Missing) service=$($after.ServiceStatus) tray=$($after.TrayCount) agent=$($after.AgentCount) tunnel=$($after.TunnelCount)"
    if ($AutoLogin -and -not $NoSubmit) {
        Get-AtrustLoginState -Foreground:($ForegroundProbe -and -not $WatchMode) | Out-Null
    }
    if (-not $after.Healthy) {
        Write-Log "login did not produce a healthy tunnel; possible causes: focus not in the password field, invalid password, MFA/session policy, or aTrust rejecting simulated input"
    }
    return $after
}

function Test-ReloginCooldownElapsed {
    param([DateTime]$LastAttemptAt)

    if ($ReloginCooldownSeconds -le 0 -or $LastAttemptAt -eq [DateTime]::MinValue) {
        return $true
    }

    $elapsed = ((Get-Date) - $LastAttemptAt).TotalSeconds
    if ($elapsed -lt $ReloginCooldownSeconds) {
        $remaining = [Math]::Ceiling($ReloginCooldownSeconds - $elapsed)
        Write-Log "login attempt skipped by cooldown; retry in ${remaining}s"
        return $false
    }

    return $true
}

function Invoke-AtrustLoginForWatch {
    param([string]$Reason)

    try {
        Write-Log "$Reason; attempting aTrust login"
        Login-Atrust -WatchMode | Out-Null
        return $true
    } catch {
        Write-Log "watch login attempt failed: $($_.Exception.Message); watch will continue"
        return $false
    }
}

function Recover-Atrust {
    param([switch]$Silent)

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
        Start-AtrustTray -TrayPath $current.TrayPath -Silent:$Silent
        Start-Sleep -Seconds 10
    }

    $after = Get-AtrustSnapshot
    Write-Log "after recover: healthy=$($after.Healthy) missing=$($after.Missing) service=$($after.ServiceStatus) tray=$($after.TrayCount) agent=$($after.AgentCount) tunnel=$($after.TunnelCount)"
    if (-not $after.Healthy -and -not $after.TunnelCount) {
        Write-Log "tunnel is still absent; saved login, MFA, or service-side session policy may require manual login"
    }
    return $after
}

function Invoke-AtrustRecoverForWatch {
    try {
        return (Recover-Atrust -Silent)
    } catch {
        Write-Log "watch recovery failed: $($_.Exception.Message); watch will continue"
        return (Get-AtrustSnapshot)
    }
}

function Watch-Atrust {
    if ($IntervalSeconds -lt 10) {
        throw "IntervalSeconds must be at least 10."
    }
    if ($ConsecutiveFailures -lt 1) {
        throw "ConsecutiveFailures must be at least 1."
    }
    if ($ReloginCooldownSeconds -lt 0) {
        throw "ReloginCooldownSeconds must be zero or greater."
    }
    if ($MaxReloginAttemptsPerLogout -lt 1) {
        throw "MaxReloginAttemptsPerLogout must be at least 1."
    }
    if ($UnknownLoginStateThreshold -lt 1) {
        throw "UnknownLoginStateThreshold must be at least 1."
    }

    if ($ForegroundProbe) {
        Write-Log "ForegroundProbe is ignored during watch; background WindowCapture monitoring is enforced"
    }

    Write-Log "watch started interval=${IntervalSeconds}s consecutiveFailures=$ConsecutiveFailures maxRecoveries=$MaxRecoveries maxChecks=$MaxChecks reloginCooldown=${ReloginCooldownSeconds}s maxReloginAttemptsPerLogout=$MaxReloginAttemptsPerLogout unknownThreshold=$UnknownLoginStateThreshold restartClientOnExit=$RestartClientOnExit dryRun=$DryRun"
    $failureCount = 0
    $recoveries = 0
    $checks = 0
    $lastLoginAttemptAt = [DateTime]::MinValue
    $unknownLoginStateCount = 0
    $confirmedLogoutActive = $false
    $reloginAttemptsForLogout = 0
    $lastLoginStateName = $null
    while ($true) {
        $checks += 1
        try {
            $snapshot = Get-AtrustSnapshot
            if ($snapshot.Healthy) {
                if ($failureCount -gt 0) {
                    Write-Log "health restored without recovery"
                }
                $failureCount = 0
                if ($AutoLogin -and $ProbeLoginState) {
                    $loginState = Get-AtrustLoginState | Select-Object -Last 1
                    Write-Log "healthy service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount) loginState=$($loginState.State)"
                    $previousLoginStateName = $lastLoginStateName
                    $lastLoginStateName = $loginState.State
                    if ($loginState.State -eq "LoggedOut" -and $previousLoginStateName -and $previousLoginStateName -ne "LoggedOut" -and $confirmedLogoutActive -and $reloginAttemptsForLogout -ge $MaxReloginAttemptsPerLogout) {
                        Write-Log "explicit logged-out UI detected after $previousLoginStateName state; resetting relogin attempts for the visible login page"
                        $confirmedLogoutActive = $false
                        $reloginAttemptsForLogout = 0
                        $unknownLoginStateCount = 0
                    }
                    if ($loginState.State -eq "LoggedOut") {
                        $unknownLoginStateCount = 0
                        $confirmedLogoutActive = $true
                        if ($reloginAttemptsForLogout -ge $MaxReloginAttemptsPerLogout) {
                            Write-Log "logged-out UI still detected; relogin attempts exhausted for this logout event [$reloginAttemptsForLogout/$MaxReloginAttemptsPerLogout]"
                        } elseif (Test-ReloginCooldownElapsed -LastAttemptAt $lastLoginAttemptAt) {
                            $lastLoginAttemptAt = Get-Date
                            $reloginAttemptsForLogout += 1
                            Invoke-AtrustLoginForWatch -Reason "logged-out UI detected; relogin attempt [$reloginAttemptsForLogout/$MaxReloginAttemptsPerLogout]" | Out-Null
                            $recoveries += 1
                            if ($MaxRecoveries -gt 0 -and $recoveries -ge $MaxRecoveries) {
                                Write-Log "watch stopped after MaxRecoveries=$MaxRecoveries"
                                return
                            }
                        }
                    } elseif ($loginState.State -eq "Unknown") {
                        $unknownLoginStateCount += 1
                        if ($confirmedLogoutActive) {
                            Write-Log "unknown login-state after confirmed logout[$unknownLoginStateCount]; relogin attempts used [$reloginAttemptsForLogout/$MaxReloginAttemptsPerLogout]"
                        } elseif ($unknownLoginStateCount -le $UnknownLoginStateThreshold) {
                            Write-Log "unknown login-state[$unknownLoginStateCount/$UnknownLoginStateThreshold]; staying silent until LoggedOut is confirmed"
                        } elseif ($unknownLoginStateCount -eq ($UnknownLoginStateThreshold + 1)) {
                            Write-Log "unknown login-state threshold reached; foreground login is blocked because logout is not confirmed"
                        }
                        if ($confirmedLogoutActive -and $reloginAttemptsForLogout -gt 0) {
                            Write-Log "confirmed logout still unresolved while login-state is Unknown; not foregrounding or consuming relogin attempts until LoggedOut is explicitly visible"
                        }
                    } else {
                        $unknownLoginStateCount = 0
                        $confirmedLogoutActive = $false
                        $reloginAttemptsForLogout = 0
                    }
                } else {
                    Write-Log "healthy service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount)"
                }
            } else {
                $clientExited = -not $snapshot.TrayCount -or -not $snapshot.MainTrayCount
                if ($clientExited -and -not $RestartClientOnExit) {
                    $failureCount = 0
                    $unknownLoginStateCount = 0
                    $confirmedLogoutActive = $false
                    $reloginAttemptsForLogout = 0
                    $lastLoginStateName = $null
                    Write-Log "client not running; respecting manual exit and not starting aTrust tray missing=$($snapshot.Missing) service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) mainTray=$($snapshot.MainTrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount)"
                } else {
                    $failureCount += 1
                    Write-Log "unhealthy[$failureCount/$ConsecutiveFailures] missing=$($snapshot.Missing) service=$($snapshot.ServiceStatus) tray=$($snapshot.TrayCount) agent=$($snapshot.AgentCount) tunnel=$($snapshot.TunnelCount)"
                    if ($failureCount -ge $ConsecutiveFailures) {
                        Invoke-AtrustRecoverForWatch | Out-Null
                        $recoveries += 1
                        $failureCount = 0
                        if ($MaxRecoveries -gt 0 -and $recoveries -ge $MaxRecoveries) {
                            Write-Log "watch stopped after MaxRecoveries=$MaxRecoveries"
                            return
                        }
                    }
                }
            }
        } catch {
            Write-Log "watch iteration failed: $($_.Exception.Message); watch will continue"
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
        $sourcePath = [IO.Path]::GetFullPath($PSCommandPath)
        $targetPath = [IO.Path]::GetFullPath($InstalledScriptPath)
        if ($sourcePath -ieq $targetPath) {
            Write-Log "helper already running from installed path; copy skipped"
        } else {
            Copy-Item -Path $PSCommandPath -Destination $InstalledScriptPath -Force
        }
    }

    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstalledScriptPath`" -Action watch -IntervalSeconds $IntervalSeconds -ConsecutiveFailures $ConsecutiveFailures -MaxRecoveries $MaxRecoveries -ReloginCooldownSeconds $ReloginCooldownSeconds -MaxReloginAttemptsPerLogout $MaxReloginAttemptsPerLogout -UnknownLoginStateThreshold $UnknownLoginStateThreshold -InputMethod $InputMethod -PostLoginWaitSeconds $PostLoginWaitSeconds"
    if ($Username) {
        $taskCommand += " -Username `"$((Escape-CommandArgument -Value $Username))`""
    }
    if ($AutoLogin) {
        $taskCommand += " -AutoLogin"
    }
    if ($AutoLogin -or $ProbeLoginState) {
        $taskCommand += " -ProbeLoginState"
    }
    if ($RestartClientOnExit) {
        $taskCommand += " -RestartClientOnExit"
    }
    if ($ForegroundProbe) {
        Write-Log "ForegroundProbe is ignored for installed watch; background monitoring is enforced"
    }
    $runnerCommand = "@echo off`r`nstart `"`" /min $taskCommand`r`n"
    $launcherCommand = "cmd.exe /c $RunnerCmdPath"
    $startupCommand = "@echo off`r`ncall `"$RunnerCmdPath`"`r`n"
    Invoke-Or-DryRun "write watch launcher $RunnerCmdPath" {
        Set-Content -Path $RunnerCmdPath -Value $runnerCommand -Encoding ASCII
    }
    Invoke-Or-DryRun "create scheduled task $TaskName" {
        & schtasks.exe /Create /TN $TaskName /TR $launcherCommand /SC ONLOGON /F | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Remove-StartupFallbackIfPresent
            Remove-RunRegistryFallbackIfPresent
        } else {
            Write-Log "schtasks /Create failed with exit code $LASTEXITCODE; falling back to Startup folder"
            try {
                Set-Content -Path $StartupFilePath -Value $startupCommand -Encoding ASCII -ErrorAction Stop
                Write-Log "created Startup fallback: $StartupFilePath"
                Remove-RunRegistryFallbackIfPresent
            } catch {
                Write-Log "Startup fallback failed: $($_.Exception.Message); falling back to HKCU Run"
                Remove-StartupFallbackIfPresent
                Set-RunRegistryFallback -Command $launcherCommand
            }
        }
    }
    Write-Log "launcher command: $launcherCommand"
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
        if (Test-Path $RunnerCmdPath) {
            Remove-Item -Path $RunnerCmdPath -Force
            Write-Log "removed watch launcher: $RunnerCmdPath"
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
    if (Test-Path $RunnerCmdPath) {
        ""
        "Watch launcher:"
        $RunnerCmdPath
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
    "login-state" { Show-LoginState }
    "login" { Login-Atrust | Format-List }
    "recover" { Recover-Atrust | Format-List }
    "watch" { Watch-Atrust }
    "save-credential" { Save-AtrustCredential }
    "clear-credential" { Clear-AtrustCredential }
    "credential-status" { Show-CredentialStatus }
    "install-task" {
        Install-WatchTask
        if (-not $DryRun) {
            Show-TaskStatus
        }
    }
    "uninstall-task" { Uninstall-WatchTask }
    "task-status" { Show-TaskStatus }
}
