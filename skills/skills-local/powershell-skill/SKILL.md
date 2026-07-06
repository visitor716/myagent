---
name: powershell-skill
description: Run Windows PowerShell safely from WSL/Codex using EncodedCommand and PowerShell 7 by default. Use when Codex needs to call PowerShell, pwsh, Windows command-line tools, WMI/CIM, registry, powercfg, Get-NetAdapter, scheduled tasks, Windows paths, or any Windows-side automation from WSL; use especially when scripts contain $env:, $_, JSON, regex, backslashes, or quoted paths.
---

# PowerShell Skill

## Overview

Use this skill before running Windows-side PowerShell from WSL. Prefer the bundled wrapper so Bash does not expand PowerShell variables or corrupt JSON, regex, or Windows paths.

The helper reads PowerShell code from stdin or `--file`, prefixes `$ProgressPreference = 'SilentlyContinue'`, encodes the script as UTF-16LE Base64, and runs `-EncodedCommand`.

## Default Command

Use the skill wrapper:

```bash
/home/zhanxp/projects/myagent/skills/skills-local/powershell-skill/scripts/invoke-powershell-encoded.sh <<'PS'
$PSVersionTable.PSVersion.ToString()
PS
```

Use a single-quoted heredoc marker (`<<'PS'`) so Bash passes the script body literally.

## PowerShell Selection

Default to the newest Windows PowerShell 7+ executable:

1. Use `POWERSHELL_EXE` only when explicitly set for the current command.
2. Prefer `pwsh.exe` from PATH.
3. Prefer the latest installed `pwsh.exe` under the user or Program Files PowerShell roots.
4. Fall back to Windows PowerShell 5.1 only when PowerShell 7 is unavailable.

When version matters, verify with:

```bash
/home/zhanxp/projects/myagent/skills/skills-local/powershell-skill/scripts/invoke-powershell-encoded.sh <<'PS'
[pscustomobject]@{
  Edition = $PSVersionTable.PSEdition
  Version = $PSVersionTable.PSVersion.ToString()
  Exe = (Get-Process -Id $PID).Path
} | ConvertTo-Json -Compress
PS
```

## Usage Rules

- Prefer this helper over `powershell.exe -Command "..."` for anything non-trivial.
- Put complex values inside the heredoc script, a temp file, or JSON read by the script; do not assemble them through Bash quoting.
- Use `--file path/to/script.ps1` when the script is long or reused.
- Read command output before claiming success.
- If a command requires Administrator rights or UAC, report the elevation boundary and use a temporary script/result file pattern when output must be captured.
- Do not install PowerShell or change system policy unless the user explicitly asks.

## Examples

Windows-side process lookup:

```bash
/home/zhanxp/projects/myagent/skills/skills-local/powershell-skill/scripts/invoke-powershell-encoded.sh <<'PS'
Get-Process | Where-Object { $_.ProcessName -match 'clash|pwsh|powershell' } |
  Select-Object Id,ProcessName,Path |
  Format-Table -AutoSize
PS
```

Windows path and JSON without Bash escaping:

```bash
/home/zhanxp/projects/myagent/skills/skills-local/powershell-skill/scripts/invoke-powershell-encoded.sh <<'PS'
$path = 'C:\Program Files\PowerShell'
[pscustomobject]@{ Exists = Test-Path $path; Path = $path; User = $env:USERNAME } |
  ConvertTo-Json -Compress
PS
```

## Anti-Patterns

- Avoid `powershell.exe -Command "$x = ..."` from Bash.
- Avoid manually escaping every `$`, backslash, quote, and JSON brace.
- Avoid direct `powercfg.exe` or other Windows commands from Bash when PATH/interop is uncertain; call them from the PowerShell heredoc.
