#Requires -Version 5.1

<#
.SYNOPSIS
    Reports local fixed-disk capacity, free space, and warning status.

.DESCRIPTION
    Queries Win32_LogicalDisk for local fixed drives (DriveType 3) and classifies
    each volume as OK, Warning, or Critical based on percent free. Thresholds
    default to the repository example config (15% warning, 5% critical) and can
    be overridden on the command line.

    This script is read-only. It never deletes files or changes disk configuration.

.PARAMETER WarningPercentFree
    Percent free at or below which a volume is Warning. Default comes from config.

.PARAMETER CriticalPercentFree
    Percent free at or below which a volume is Critical. Default comes from config.

.PARAMETER ComputerName
    Computer to query. Defaults to the local computer. Remote queries use existing
    CIM/WinRM permissions; no credentials are stored.

.PARAMETER OutputPath
    Optional destination file (.csv, .json, or .html).

.PARAMETER FailOnWarning
    Set a non-zero exit code when any volume is Warning (1) or Critical (2).
    Useful when the script is run from Task Scheduler.

.EXAMPLE
    .\Get-DiskSpaceReport.ps1

    Prints a table of local volumes and their status.

.EXAMPLE
    .\Get-DiskSpaceReport.ps1 -WarningPercentFree 20 -CriticalPercentFree 10 -OutputPath .\output\disks.csv

    Uses custom thresholds and writes CSV.

.EXAMPLE
    .\Get-DiskSpaceReport.ps1 -FailOnWarning
    if ($LASTEXITCODE -ne 0) { Write-Host 'Disk space below threshold.' }

.NOTES
    Windows only. Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter()]
    [ValidateRange(1, 99)]
    [int]$WarningPercentFree,

    [Parameter()]
    [ValidateRange(1, 99)]
    [int]$CriticalPercentFree,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$FailOnWarning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path (Join-Path (Join-Path $repoRoot 'modules') 'WinAutomate.Common') 'WinAutomate.Common.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest)) {
    throw "Required module not found at '$moduleManifest'. Run this script from a clone of the windows-automate repository."
}
Import-Module $moduleManifest -Force

$config = Get-WinAutomateConfig

if (-not $PSBoundParameters.ContainsKey('WarningPercentFree')) {
    $WarningPercentFree = [int]$config.diskSpace.warningPercentFree
}
if (-not $PSBoundParameters.ContainsKey('CriticalPercentFree')) {
    $CriticalPercentFree = [int]$config.diskSpace.criticalPercentFree
}

if ($CriticalPercentFree -gt $WarningPercentFree) {
    throw "CriticalPercentFree ($CriticalPercentFree) cannot be greater than WarningPercentFree ($WarningPercentFree)."
}

$cimParams = @{
    ClassName   = 'Win32_LogicalDisk'
    Filter      = 'DriveType=3'
    ErrorAction = 'Stop'
}

$localNames = @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '.')
if ($localNames -notcontains $ComputerName) {
    $cimParams['ComputerName'] = $ComputerName
}

Write-WinAutomateLog -Message "Querying fixed disks on '$ComputerName'."

$volumes = @(Get-CimInstance @cimParams | Where-Object { $_ })
if ($volumes.Count -eq 0) {
    Write-WinAutomateLog -Level WARN -Message "No local fixed disks were returned for '$ComputerName'."
}

$report = @(
    $volumes | ForEach-Object {
        $percentFree = $null
        $status = 'Unknown'

        if ($_.Size -and $_.Size -gt 0) {
            $percentFree = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            if ($percentFree -le $CriticalPercentFree) {
                $status = 'Critical'
            }
            elseif ($percentFree -le $WarningPercentFree) {
                $status = 'Warning'
            }
            else {
                $status = 'OK'
            }
        }

        [pscustomobject]@{
            ComputerName = $ComputerName
            DeviceID     = $_.DeviceID
            VolumeName   = $_.VolumeName
            FileSystem   = $_.FileSystem
            Size         = ConvertTo-ByteSize -Bytes $_.Size
            Used         = if ($null -ne $_.Size -and $null -ne $_.FreeSpace) {
                ConvertTo-ByteSize -Bytes ([int64]$_.Size - [int64]$_.FreeSpace)
            }
            else {
                'N/A'
            }
            FreeSpace    = ConvertTo-ByteSize -Bytes $_.FreeSpace
            PercentFree  = $percentFree
            Status       = $status
            SizeBytes    = $_.Size
            FreeBytes    = $_.FreeSpace
        }
    }
)

if ($OutputPath) {
    $exported = $report | Export-WinAutomateReport -Path $OutputPath
    Write-WinAutomateLog -Message "Disk report written to '$($exported.FullName)'."
}

$report | Write-Output

if ($FailOnWarning) {
    if ($report | Where-Object { $_.Status -eq 'Critical' }) {
        exit 2
    }
    if ($report | Where-Object { $_.Status -eq 'Warning' }) {
        exit 1
    }
}
