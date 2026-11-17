# Disables Fast Startup (Hibernate)
Write-Host "=== Disabling Fast Startup & Hibernate ===" -ForegroundColor Cyan

$result = powercfg /h off 2>&1
Write-Host $result

# Verify registry
$key = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue
if ($key.HiberbootEnabled -eq 0) {
    Write-Host "✓ Fast Startup DISABLED" -ForegroundColor Green
} else {
    Write-Host "✗ Fast Startup still enabled or could not verify." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Power state ===" -ForegroundColor Cyan
powercfg /a 2>&1 | Write-Host

Write-Host ""
Write-Host "Done." -ForegroundColor Green
