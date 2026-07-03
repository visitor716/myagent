[CmdletBinding()]
param(
    [string]$DumpPath = 'C:\Windows\MEMORY.DMP',
    [string]$OutputDir = "$env:USERPROFILE\Desktop\dump-analysis",
    [string]$DebuggerPath = '',
    [switch]$CopyDump,
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

    $localDir = Join-Path $env:TEMP 'myagent-analyze-bugcheck-dump'
    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
    $localPath = Join-Path $localDir 'analyze-bugcheck-dump.ps1'
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
        '-DumpPath', (Quote-Argument $DumpPath),
        '-OutputDir', (Quote-Argument $OutputDir),
        '-DebuggerPath', (Quote-Argument $DebuggerPath)
    )
    if ($CopyDump) {
        $args += '-CopyDump'
    }
    if ($PauseAfterRun) {
        $args += '-PauseAfterRun'
    }

    Write-Host 'Administrator rights are required to read Windows crash dumps. Requesting elevation...'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs | Out-Null
}

function Find-Debugger {
    if ($DebuggerPath -and (Test-Path -LiteralPath $DebuggerPath)) {
        return $DebuggerPath
    }

    $explicitCandidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\kd.exe",
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\kd.exe"
    )

    foreach ($candidate in $explicitCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $commandNames = @('cdb.exe', 'kd.exe', 'windbg.exe', 'WinDbgX.exe')
    foreach ($name in $commandNames) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    $roots = @(
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps",
        "$env:ProgramFiles\WindowsApps"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($name in $commandNames) {
            $match = Get-ChildItem -LiteralPath $root -Filter $name -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }

    return $null
}

function Invoke-DebuggerAnalysis {
    param(
        [string]$DebuggerPath,
        [string]$LocalDump,
        [string]$LogPath
    )

    $symbolPath = 'srv*C:\Symbols*https://msdl.microsoft.com/download/symbols'
    $ext = [IO.Path]::GetFileName($DebuggerPath).ToLowerInvariant()
    $debuggerDir = Split-Path -Parent $DebuggerPath
    $extensionDir = Join-Path $OutputDir 'dbgext'
    New-Item -ItemType Directory -Path $extensionDir -Force | Out-Null
    $extDll = Join-Path $extensionDir 'ext.dll'
    $kdextsDll = Join-Path $extensionDir 'kdexts.dll'
    Copy-Item -LiteralPath (Join-Path $debuggerDir 'winext\ext.dll') -Destination $extDll -Force
    Copy-Item -LiteralPath (Join-Path $debuggerDir 'winxp\kdexts.dll') -Destination $kdextsDll -Force
    $env:_NT_DEBUGGER_EXTENSION_PATH = (Join-Path $debuggerDir 'winext') + ';' + (Join-Path $debuggerDir 'winxp')
    $analysisCommand = '.symfix C:\Symbols; .reload /f nt; .load ' + $extDll + '; .load ' + $kdextsDll + '; !analyze -v; !devnode 0 1; !poaction; lmtn; q'

    if ($ext -in @('cdb.exe', 'kd.exe')) {
        $arguments = @(
            '-z', $LocalDump,
            '-i', 'C:\Windows\System32',
            '-y', $symbolPath,
            '-logo', $LogPath,
            '-c', $analysisCommand
        )
    }
    else {
        $arguments = @(
            '-z', $LocalDump,
            '-y', $symbolPath,
            '-c', $analysisCommand
        )
    }

    Write-Host "Running debugger: $DebuggerPath"
    Write-Host "Log path: $LogPath"
    Push-Location $debuggerDir
    try {
        & $DebuggerPath @arguments
        $exitCode = $LASTEXITCODE
        $process = [pscustomobject]@{ ExitCode = $exitCode }
        Write-Host "Debugger exit code: $($process.ExitCode)"
    }
    finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if (-not (Test-IsAdministrator)) {
    if ($NoElevate) {
        throw 'Administrator rights are required to read Windows crash dumps.'
    }
    Restart-Elevated
    exit 0
}

if (-not (Test-Path -LiteralPath $DumpPath)) {
    throw "Dump file not found: $DumpPath"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$localDump = $DumpPath
$logPath = Join-Path $OutputDir ("analysis-$timestamp.txt")
$summaryPath = Join-Path $OutputDir ("summary-$timestamp.txt")

if ($CopyDump) {
    $localDump = Join-Path $OutputDir ("MEMORY-$timestamp.DMP")
    Write-Host "Copying dump to: $localDump"
    Copy-Item -LiteralPath $DumpPath -Destination $localDump -Force
}
else {
    Write-Host "Analyzing dump in place: $localDump"
}

$debugger = Find-Debugger
if (-not $debugger) {
    @(
        "No debugger executable found.",
        'Install Microsoft WinDbg or Windows Debugging Tools, then rerun this script.',
        'Suggested winget package: Microsoft.WinDbg',
        "Dump path: $localDump"
    ) | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Get-Content -LiteralPath $summaryPath
    if ($PauseAfterRun) {
        Read-Host 'Press Enter to close'
    }
    exit 2
}

Invoke-DebuggerAnalysis -DebuggerPath $debugger -LocalDump $localDump -LogPath $logPath

@(
    "Dump: $localDump",
    "Debugger: $debugger",
    "Log: $logPath",
    '',
    'Search terms to inspect:',
    '  BUGCHECK_CODE',
    '  Probably caused by',
    '  IMAGE_NAME',
    '  MODULE_NAME',
    '  FAILURE_BUCKET_ID',
    '  DRVPOWERSTATE_SUBCODE',
    '  !poaction'
) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Get-Content -LiteralPath $summaryPath
if ($PauseAfterRun) {
    Read-Host 'Press Enter to close'
}
