#Requires -Version 5.1

<#
.SYNOPSIS
    Removes old files from temporary folders, with preview as the default.

.DESCRIPTION
    Scans one or more temp directories and deletes files older than a given
    number of days. Preview/WhatIf is the default: nothing is deleted unless
    you pass -Force. Locked files are skipped rather than causing a failure.

    Protected locations (Windows, System32, Program Files, User profiles root)
    are refused. -IncludeWindowsTemp adds %SystemRoot%\Temp only when the
    session is elevated.

.PARAMETER Path
    Directories to scan. Defaults to the current user's TEMP folder.

.PARAMETER OlderThanDays
    Only files whose LastWriteTime is at least this many days ago are eligible.
    Default is 7, or the value in config.

.PARAMETER IncludeWindowsTemp
    Also scan %SystemRoot%\Temp. Requires an elevated session.

.PARAMETER Force
    Actually delete eligible files. Without -Force the script only reports
    what would be removed.

.PARAMETER LogPath
    Optional log file for progress and skipped files.

.EXAMPLE
    .\Clear-TempFiles.ps1

    Preview files older than 7 days in %TEMP%. No deletions.

.EXAMPLE
    .\Clear-TempFiles.ps1 -OlderThanDays 3 -WhatIf

    Explicit dry run for files older than 3 days.

.EXAMPLE
    .\Clear-TempFiles.ps1 -Force -IncludeWindowsTemp

    Delete eligible files in user TEMP and Windows\Temp (admin required).

.NOTES
    Supports -WhatIf and -Confirm via SupportsShouldProcess.
    Windows only. Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string[]]$Path,

    [Parameter()]
    [ValidateRange(0, 3650)]
    [int]$OlderThanDays,

    [Parameter()]
    [switch]$IncludeWindowsTemp,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path (Join-Path (Join-Path $repoRoot 'modules') 'WinAutomate.Common') 'WinAutomate.Common.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest)) {
    throw "Required module not found at '$moduleManifest'. Run this script from a clone of the windows-automate repository."
}
Import-Module $moduleManifest -Force

function Test-IsProtectedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    $full = [System.IO.Path]::GetFullPath($Candidate)
    $protected = @(
        $env:SystemRoot
        (Join-Path $env:SystemRoot 'System32')
        ${env:ProgramFiles}
        ${env:ProgramFiles(x86)}
        $env:ProgramData
        (Split-Path $env:USERPROFILE -Parent)
    ) | Where-Object { $_ }

    foreach ($root in $protected) {
        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        if ([string]::Equals($full.TrimEnd('\'), $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

$config = Get-WinAutomateConfig

if (-not $PSBoundParameters.ContainsKey('OlderThanDays')) {
    $OlderThanDays = [int]$config.tempCleanup.olderThanDays
}

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @($env:TEMP)
}

if ($IncludeWindowsTemp -or (-not $PSBoundParameters.ContainsKey('IncludeWindowsTemp') -and $config.tempCleanup.includeWindowsTemp)) {
    if (-not (Test-ElevatedSession)) {
        throw 'Scanning Windows\Temp requires an elevated PowerShell session. Re-run as Administrator or omit -IncludeWindowsTemp.'
    }
    $windowsTemp = Join-Path $env:SystemRoot 'Temp'
    if ($Path -notcontains $windowsTemp) {
        $Path += $windowsTemp
    }
}

# Preview is the default. -Force is required to delete; -WhatIf still wins.
if (-not $Force) {
    $WhatIfPreference = $true
    Write-WinAutomateLog -Level WARN -Message 'Preview mode. Pass -Force to delete files (still honors -WhatIf / -Confirm).' -LogPath $LogPath
}

$cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)
$removedCount = 0
$removedBytes = [int64]0
$skippedCount = 0
$candidateCount = 0

$targets = @(
    $Path | ForEach-Object {
        $resolved = $_
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path (Get-Location) $resolved
        }

        if (-not (Test-Path -LiteralPath $resolved)) {
            Write-WinAutomateLog -Level WARN -Message "Skipping missing path '$resolved'." -LogPath $LogPath
            return
        }

        $item = Get-Item -LiteralPath $resolved -Force
        if (-not $item.PSIsContainer) {
            throw "Path '$resolved' is a file. Supply a directory."
        }

        if (Test-IsProtectedPath -Candidate $item.FullName) {
            throw "Refusing to scan protected path '$($item.FullName)'."
        }

        $item.FullName
    }
)

Write-WinAutomateLog -Message ("Scanning {0} path(s) for files last written before {1:yyyy-MM-dd}." -f $targets.Count, $cutoff) -LogPath $LogPath

foreach ($directory in $targets) {
    $files = @(
        Get-ChildItem -LiteralPath $directory -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -le $cutoff }
    )

    foreach ($file in $files) {
        $candidateCount++
        $descriptor = '{0} ({1}, last write {2:yyyy-MM-dd})' -f $file.FullName, (ConvertTo-ByteSize -Bytes $file.Length), $file.LastWriteTime

        if ($PSCmdlet.ShouldProcess($descriptor, 'Remove temporary file')) {
            try {
                $length = $file.Length
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removedCount++
                $removedBytes += $length
                Write-WinAutomateLog -Message "Removed $descriptor" -LogPath $LogPath
            }
            catch {
                $skippedCount++
                Write-WinAutomateLog -Level WARN -Message "Skipped '$($file.FullName)': $($_.Exception.Message)" -LogPath $LogPath
            }
        }
        else {
            # WhatIf / declined Confirm still counts as a candidate for the summary.
        }
    }
}

$summary = [pscustomobject]@{
    PreviewOnly    = (-not $Force.IsPresent) -or ($WhatIfPreference -eq 'Continue')
    PathsScanned   = $targets
    OlderThanDays  = $OlderThanDays
    Cutoff         = $cutoff
    CandidateFiles = $candidateCount
    RemovedFiles   = $removedCount
    SkippedFiles   = $skippedCount
    BytesFreed     = $removedBytes
    SizeFreed      = ConvertTo-ByteSize -Bytes $removedBytes
}

Write-WinAutomateLog -Message ("Summary: {0} candidate(s), {1} removed, {2} skipped, {3} freed." -f $candidateCount, $removedCount, $skippedCount, $summary.SizeFreed) -LogPath $LogPath

Write-Output $summary
