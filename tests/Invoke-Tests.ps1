#Requires -Version 5.1

<#
.SYNOPSIS
    Runs Pester tests for the windows-automate repository.

.DESCRIPTION
    Imports Pester 5+ and invokes tests under /tests. If Pester is not installed,
    the script prints the install command and exits without running tests.

.PARAMETER Path
    Test path passed to Pester. Defaults to the tests folder next to this script.

.EXAMPLE
    .\Invoke-Tests.ps1

.EXAMPLE
    .\Invoke-Tests.ps1 -Path .\WinAutomate.Common.Tests.ps1

.NOTES
    Install Pester (once per user):

        Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = $PSScriptRoot
}

$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.0.0' } |
    Select-Object -First 1

if (-not $pester) {
    Write-Warning 'Pester 5.0.0 or later is not installed.'
    Write-Warning 'Install it for the current user with:'
    Write-Warning '  Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck'
    Write-Warning 'Then re-run:  .\tests\Invoke-Tests.ps1'
    exit 1
}

Import-Module Pester -MinimumVersion 5.0.0
$configuration = New-PesterConfiguration
$configuration.Run.Path = @($Path)
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $configuration
