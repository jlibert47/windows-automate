# windows-automate

PowerShell automation for Windows machines. This repository is a small, opinionated home for scripts you can run today and grow over time: inventory, disk reporting, temp cleanup, plus a shared helper module.

Scripts target **Windows PowerShell 5.1** and **PowerShell 7+** (`pwsh`). They use CIM (not legacy WMI), approved verbs, comment-based help, and `#Requires`. Destructive work defaults to preview (`-WhatIf` / no `-Force`). Nothing in this repo stores credentials or calls paid APIs.

## Requirements

- Windows 10, Windows 11, or Windows Server
- Windows PowerShell 5.1 (built in) or PowerShell 7+ ([install guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows))
- Permission to run local scripts (see [Execution policy](#execution-policy))
- Administrator only when a script says so (for example, scanning `C:\Windows\Temp`)

Optional:

- [Pester 5+](https://pester.dev/) for tests
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) for static analysis
- VS Code with the [PowerShell extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell) (recommended in `.vscode/extensions.json`)

## Folder layout

```text
windows-automate/
├── scripts/                         # Runnable automation (start here)
│   ├── Get-MachineInventory.ps1
│   ├── Get-DiskSpaceReport.ps1
│   └── Clear-TempFiles.ps1
├── modules/
│   └── WinAutomate.Common/          # Shared helpers imported by the scripts
├── config/
│   └── settings.example.json        # Sample settings (no secrets)
├── tests/                           # Pester 5 tests + runner
├── output/                          # Created at runtime; gitignored
├── logs/                            # Created at runtime; gitignored
├── PSScriptAnalyzerSettings.psd1
└── README.md
```

| Path | Purpose |
| --- | --- |
| `scripts/` | End-user scripts with comment-based help and parameters |
| `modules/` | Reusable module code. Scripts import `WinAutomate.Common` from source |
| `config/` | Example configuration. Copy to `settings.json` for local overrides (`settings.json` is gitignored) |
| `tests/` | Pester tests for the shared module and a smoke check that scripts ship help |

## How to run

Clone the repo, then call a script by path. The scripts import `modules/WinAutomate.Common` relative to `$PSScriptRoot`, so run them from a full checkout.

### PowerShell 7+ (`pwsh`)

```powershell
cd path\to\windows-automate

pwsh -NoProfile -File .\scripts\Get-MachineInventory.ps1
pwsh -NoProfile -File .\scripts\Get-DiskSpaceReport.ps1
pwsh -NoProfile -File .\scripts\Clear-TempFiles.ps1
```

### Windows PowerShell 5.1

```powershell
cd path\to\windows-automate

powershell.exe -NoProfile -File .\scripts\Get-MachineInventory.ps1
powershell.exe -NoProfile -File .\scripts\Get-DiskSpaceReport.ps1
powershell.exe -NoProfile -File .\scripts\Clear-TempFiles.ps1
```

From an already-open prompt:

```powershell
Set-Location path\to\windows-automate
Get-Help .\scripts\Get-MachineInventory.ps1 -Full
.\scripts\Get-MachineInventory.ps1 -OutputPath .\output\inventory.json
.\scripts\Get-DiskSpaceReport.ps1 -FailOnWarning
.\scripts\Clear-TempFiles.ps1                  # preview only
.\scripts\Clear-TempFiles.ps1 -Force           # delete eligible files
```

### Execution policy

If Windows blocks `.ps1` files:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

To run a single file without changing policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-DiskSpaceReport.ps1
```

Remote CIM queries (`-ComputerName`) use **your existing WinRM/CIM permissions**. This project never prompts for or saves passwords.

## Starter scripts

### `Get-MachineInventory.ps1`

Local (or remote) snapshot: OS, hardware, memory, disks, network adapters, PowerShell version, and pending reboot. Optional hotfix list.

```powershell
.\scripts\Get-MachineInventory.ps1
.\scripts\Get-MachineInventory.ps1 -OutputPath .\output\inventory.html
.\scripts\Get-MachineInventory.ps1 -ComputerName WORKSTATION01
```

### `Get-DiskSpaceReport.ps1`

Fixed volumes (DriveType 3) with OK / Warning / Critical based on percent free. Defaults come from config (15% warning, 5% critical). `-FailOnWarning` sets exit code 1 (warning) or 2 (critical) for Task Scheduler.

```powershell
.\scripts\Get-DiskSpaceReport.ps1
.\scripts\Get-DiskSpaceReport.ps1 -WarningPercentFree 20 -OutputPath .\output\disks.csv
```

### `Clear-TempFiles.ps1`

Deletes files older than N days from temp folders. **Preview is the default** — pass `-Force` to delete. Still honors `-WhatIf` and `-Confirm`. Refuses protected paths. `-IncludeWindowsTemp` adds `%SystemRoot%\Temp` and requires elevation.

```powershell
.\scripts\Clear-TempFiles.ps1
.\scripts\Clear-TempFiles.ps1 -OlderThanDays 3 -WhatIf
.\scripts\Clear-TempFiles.ps1 -Force
```

## Shared module

`WinAutomate.Common` exports:

- `ConvertTo-ByteSize` — human-readable sizes (invariant culture)
- `Get-WinAutomateConfig` / `Get-WinAutomateRepoRoot`
- `Export-WinAutomateReport` — CSV, JSON, or HTML from the file extension
- `Test-ElevatedSession`
- `Write-WinAutomateLog`

Import from source while you iterate:

```powershell
Import-Module .\modules\WinAutomate.Common\WinAutomate.Common.psd1 -Force
```

## Configuration

Copy the example file and edit locally. Do not commit secrets; `config/settings.json` is gitignored.

```powershell
Copy-Item .\config\settings.example.json .\config\settings.json
```

The example file only contains thresholds and output folder names. Keep API keys, passwords, and certificates out of git (see `.gitignore` for `*.pfx`, `*.clixml`, `secrets/`, and similar).

## Tests

Pester is optional. If it is not installed, `tests\Invoke-Tests.ps1` prints the install command and exits.

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
.\tests\Invoke-Tests.ps1
```

To run Pester yourself:

```powershell
Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path .\tests
```

## Static analysis (optional)

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path .\scripts, .\modules, .\tests -Settings .\PSScriptAnalyzerSettings.psd1 -Recurse
```

## Contribution notes

- Keep changes small: one script or one module concern per pull request.
- Use [approved verbs](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) for file and function names (`Get-`, `Clear-`, `Test-`, not `Fetch-` or `Do-`).
- Add comment-based help (`<# .SYNOPSIS ... #>`) and at least one `.EXAMPLE` on every new script.
- Set `$ErrorActionPreference = 'Stop'` in scripts; use `#Requires -Version 5.1` unless a script truly needs 7+.
- Destructive scripts must implement `SupportsShouldProcess` and default to preview or confirmation.
- Prefer `Get-CimInstance` over `Get-WmiObject`. Do not hard-code secrets or call paid external APIs.
- Put reusable logic in `modules/WinAutomate.Common` and cover it with a Pester test when the behavior is non-trivial.
- Local machine output belongs in `output/` or `logs/`; sample config belongs in `config/*.example.json`.
- Conventional commit messages work well here (`feat:`, `fix:`, `docs:`, `test:`).

Read existing scripts before adding a new one — match their parameter style, help block, and module import.
