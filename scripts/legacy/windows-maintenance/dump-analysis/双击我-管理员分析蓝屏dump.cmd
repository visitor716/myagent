@echo off
setlocal
set "SCRIPT=%TEMP%\myagent-analyze-bugcheck-dump\analyze-bugcheck-dump.ps1"
set "OUTDIR=%USERPROFILE%\Desktop\dump-analysis"
set "DEBUGGER=C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
set "ERRLOG=%OUTDIR%\launcher-error.txt"

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo Requesting administrator permission to analyze C:\Windows\MEMORY.DMP...
echo If a UAC window appears, click Yes.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ''%SCRIPT%'' -OutputDir ''%OUTDIR%'' -DebuggerPath ''%DEBUGGER%'' -PauseAfterRun' } catch { $_ | Out-File -FilePath '%ERRLOG%' -Encoding utf8; throw }"

echo.
echo After the administrator window finishes, results will be under:
echo %OUTDIR%
pause
