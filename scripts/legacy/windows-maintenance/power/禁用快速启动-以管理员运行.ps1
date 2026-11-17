# Run this script as Administrator (right-click → Run as Administrator)
# Disables Fast Startup (Hibernate) to prevent driver power transition BSODs

Write-Host "=== Disabling Fast Startup & Hibernate ===" -ForegroundColor Cyan

$result = powercfg /h off 2>&1
Write-Host $result

# Verify registry
$key = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue
if ($key.HiberbootEnabled -eq 0) {
    Write-Host "✓ Fast Startup DISABLED" -ForegroundColor Green
} else {
    Write-Host "✗ Fast Startup still enabled. Try rebooting once and re-running." -ForegroundColor Red
}

Write-Host "`n=== Checking power state ===" -ForegroundColor Cyan
$hibernate = powercfg /a 2>&1
Write-Host $hibernate

Write-Host "`nDone. You can close this window." -ForegroundColor Green
Read-Host "Press Enter to exit"
