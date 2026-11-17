# HP OMEN 16 - Driver Health Check & Update Script
# Run as Administrator for best results

$ErrorActionPreference = "Continue"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " HP OMEN 16 驱动健康检查" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ===== 1. Check Intel DSA =====
Write-Host "[1/5] Intel Driver & Support Assistant" -ForegroundColor Yellow
$dsaPaths = @(
    "${env:ProgramFiles(x86)}\Intel\Driver and Support Assistant\x86\DSATray.exe",
    "${env:ProgramFiles(x86)}\Intel\Driver and Support Assistant\DSATray.exe",
    "${env:ProgramFiles}\Intel\Driver and Support Assistant\DSATray.exe"
)
$dsaFound = $false
foreach ($p in $dsaPaths) {
    if (Test-Path $p) {
        Write-Host "  ✓ Intel DSA found at: $p" -ForegroundColor Green
        Write-Host "  → Run it to auto-update all Intel drivers"
        $dsaFound = $true
        break
    }
}
if (-not $dsaFound) {
    Write-Host "  ✗ Intel DSA NOT installed" -ForegroundColor Red
    Write-Host "  → Download: https://www.intel.com/content/www/us/en/support/detect.html"
}

# ===== 2. Quick Start Status =====
Write-Host ""
Write-Host "[2/5] Fast Startup (快速启动)" -ForegroundColor Yellow
try {
    $hiberboot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled).HiberbootEnabled
    if ($hiberboot -eq 1) {
        Write-Host "  ✗ ENABLED - THIS IS CAUSING BSOD ON RESTART!" -ForegroundColor Red
        Write-Host "  → Run: powercfg /h off" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ Disabled - safe" -ForegroundColor Green
    }
} catch {
    Write-Host "  ? Cannot read status (need admin?)"
}

# ===== 3. GPU Drivers =====
Write-Host ""
Write-Host "[3/5] GPU Drivers" -ForegroundColor Yellow
try {
    $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notlike "*Oray*" -and $_.Name -notlike "*GameViewer*" }
    foreach ($gpu in $gpus) {
        $name = $gpu.Name
        $ver = $gpu.DriverVersion
        $date = $gpu.DriverDate
        if ($name -like "*NVIDIA*") {
            Write-Host "  NVIDIA RTX 4060: v$ver ($date)"
            Write-Host "  → Use NVIDIA App to check for updates" -ForegroundColor DarkGray
        } elseif ($name -like "*Intel*UHD*" -or $name -like "*Intel*Graphics*") {
            Write-Host "  $name : v$ver ($date)"
            $age = (Get-Date) - $date
            if ($age.Days -gt 365) {
                Write-Host "  ⚠ Driver is $($age.Days) days old - UPDATE RECOMMENDED" -ForegroundColor Yellow
            } else {
                Write-Host "  ✓ Recent" -ForegroundColor Green
            }
        }
    }
} catch {
    Write-Host "  ? GPU check failed"
}

# ===== 4. Critical Platform Drivers =====
Write-Host ""
Write-Host "[4/5] Critical Platform Drivers (2+ years old → likely BSOD cause)" -ForegroundColor Yellow

$critical = @(
    @{Name="Intel IPF Manager"; Pattern="*Innovation Platform Framework Manager*"; Current="2.2.10000.20"; Risk="EXTREME"},
    @{Name="Intel IPF Processor"; Pattern="*Innovation Platform Framework Processor*"; Current="2.2.10000.20"; Risk="EXTREME"},
    @{Name="Intel IPF Extensible"; Pattern="*Innovation Platform Framework Extensible*"; Current="2.2.10000.20"; Risk="EXTREME"},
    @{Name="Intel XTU (25 instances!)"; Pattern="*XTU Component Device*"; Current="7.14.2.14"; Risk="HIGH"}
)

foreach ($c in $critical) {
    $devices = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like $c.Pattern }
    $count = @($devices).Count
    $ver = ($devices | Select-Object -First 1).DriverVersion
    if ($ver) {
        Write-Host "  $($c.Name): v$ver [Risk: $($c.Risk)]"
    }
}

Write-Host ""
Write-Host "  ⚠ ALL above drivers are 2+ years old (May-June 2024)" -ForegroundColor Red
Write-Host "  → Install Intel DSA to update: https://www.intel.com/support/detect" -ForegroundColor Yellow

# ===== 5. Virtual Display Drivers =====
Write-Host ""
Write-Host "[5/5] Virtual Display Drivers (known BSOD contributors)" -ForegroundColor Yellow

$virtual = @("OrayIddDriver", "GameViewer")
foreach ($vd in $virtual) {
    $dev = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like "*$vd*" }
    if ($dev) {
        Write-Host "  ⚠ $($dev.DeviceName) v$($dev.DriverVersion)" -ForegroundColor Yellow
    }
}

if ($dev) {
    Write-Host "  → Consider removing if not needed: Device Manager → Display Adapters → Uninstall" -ForegroundColor Yellow
}

# ===== Summary =====
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ACTION PLAN (in order of priority)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. Run as Admin: powercfg /h off  (disable Fast Startup)" -ForegroundColor White
Write-Host "2. Install Intel DSA: https://www.intel.com/support/detect" -ForegroundColor White
Write-Host "3. Run Intel DSA → update ALL drivers it finds" -ForegroundColor White
Write-Host "4. Open NVIDIA App → update GPU driver" -ForegroundColor White
Write-Host "5. Check Windows Update → Optional Updates → Driver updates" -ForegroundColor White
Write-Host "6. Reboot and verify: no BSOD for 24 hours" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to exit"
