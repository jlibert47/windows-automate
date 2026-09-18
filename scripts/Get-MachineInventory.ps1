#Requires -Version 5.1

<#
.SYNOPSIS
    Collects a snapshot of local Windows machine inventory.

.DESCRIPTION
    Gathers operating system, hardware, memory, disk, network, and pending-reboot
    details from a Windows computer using CIM. The result is a single object that
    can be printed to the host or exported to CSV, JSON, or HTML.

    Remote queries use the caller's existing CIM/WinRM permissions. This script
    does not prompt for, store, or invent credentials.

.PARAMETER ComputerName
    Computer to query. Defaults to the local computer.

.PARAMETER IncludeHotfixes
    Include installed hotfix IDs. This can be slow on machines with a long
    update history. Default is false unless enabled in config.

.PARAMETER OutputPath
    Optional destination file. Format is inferred from the extension
    (.csv, .json, or .html). Parent folders are created if missing.

.PARAMETER LogPath
    Optional log file for progress messages.

.EXAMPLE
    .\Get-MachineInventory.ps1

    Prints an inventory object for the local machine.

.EXAMPLE
    .\Get-MachineInventory.ps1 -OutputPath .\output\inventory.json

    Writes JSON to the output folder.

.EXAMPLE
    .\Get-MachineInventory.ps1 -ComputerName WORKSTATION01 -IncludeHotfixes

    Queries another computer using existing WinRM/CIM permissions.

.NOTES
    Windows only. Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter()]
    [switch]$IncludeHotfixes,

    [Parameter()]
    [string]$OutputPath,

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

function Get-CimData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Target
    )

    $params = @{
        ClassName   = $ClassName
        ErrorAction = 'Stop'
    }

    $localNames = @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '.')
    if ($Target -and ($localNames -notcontains $Target)) {
        $params['ComputerName'] = $Target
    }

    if ($Filter) {
        $params['Filter'] = $Filter
    }

    return Get-CimInstance @params
}

function Test-PendingReboot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $localNames = @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '.')
    $isLocal = $localNames -contains $Target

    if (-not $isLocal) {
        return 'Unknown (remote registry not queried)'
    }

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($registryPath in $paths) {
        if (Test-Path -LiteralPath $registryPath) {
            return 'Yes'
        }
    }

    $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    $pendingRenames = $null
    if ($sessionManager -and $sessionManager.PSObject.Properties['PendingFileRenameOperations']) {
        $pendingRenames = $sessionManager.PendingFileRenameOperations
    }
    if ($pendingRenames) {
        return 'Yes'
    }

    return 'No'
}

$config = Get-WinAutomateConfig
if (-not $PSBoundParameters.ContainsKey('IncludeHotfixes')) {
    if ($config.inventory.includeHotfixes) {
        $IncludeHotfixes = $true
    }
}

Write-WinAutomateLog -Message "Collecting inventory for '$ComputerName'." -LogPath $LogPath

$os = $null
$computer = $null
$bios = $null
$processor = $null
$memory = @()
$logicalDisks = @()
$adapters = @()
$hotfixes = @()

try {
    $os = Get-CimData -ClassName Win32_OperatingSystem -Target $ComputerName
}
catch {
    Write-WinAutomateLog -Level ERROR -Message "Failed to query Win32_OperatingSystem: $($_.Exception.Message)" -LogPath $LogPath
    throw
}

try {
    $computer = Get-CimData -ClassName Win32_ComputerSystem -Target $ComputerName
    $bios = Get-CimData -ClassName Win32_BIOS -Target $ComputerName
    $processor = @(Get-CimData -ClassName Win32_Processor -Target $ComputerName)[0]
    $memory = @(Get-CimData -ClassName Win32_PhysicalMemory -Target $ComputerName)
    $logicalDisks = @(Get-CimData -ClassName Win32_LogicalDisk -Target $ComputerName -Filter 'DriveType=3')
    $adapters = @(Get-CimData -ClassName Win32_NetworkAdapterConfiguration -Target $ComputerName -Filter 'IPEnabled=TRUE')
}
catch {
    Write-WinAutomateLog -Level WARN -Message "Partial inventory: $($_.Exception.Message)" -LogPath $LogPath
}

if ($IncludeHotfixes) {
    try {
        $hotfixes = @(Get-CimData -ClassName Win32_QuickFixEngineering -Target $ComputerName | Select-Object -ExpandProperty HotFixID)
    }
    catch {
        Write-WinAutomateLog -Level WARN -Message "Hotfix query failed: $($_.Exception.Message)" -LogPath $LogPath
    }
}

$totalRam = 0L
if ($computer -and $computer.TotalPhysicalMemory) {
    $totalRam = [int64]$computer.TotalPhysicalMemory
}

$diskSummary = @(
    $logicalDisks | ForEach-Object {
        [pscustomobject]@{
            DeviceID   = $_.DeviceID
            FileSystem = $_.FileSystem
            Size       = ConvertTo-ByteSize -Bytes $_.Size
            FreeSpace  = ConvertTo-ByteSize -Bytes $_.FreeSpace
            PercentFree = if ($_.Size -and $_.Size -gt 0) {
                [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            }
            else {
                $null
            }
        }
    }
)

$networkSummary = @(
    $adapters | ForEach-Object {
        $addresses = @()
        if ($_.IPAddress) {
            $addresses = @($_.IPAddress)
        }

        [pscustomobject]@{
            Description = $_.Description
            MACAddress  = $_.MACAddress
            DHCPEnabled = [bool]$_.DHCPEnabled
            IPAddress   = $addresses -join ', '
        }
    }
)

$inventory = [pscustomobject]@{
    ComputerName       = $ComputerName
    CollectedAt        = Get-Date
    Manufacturer       = if ($computer) { $computer.Manufacturer } else { $null }
    Model              = if ($computer) { $computer.Model } else { $null }
    SerialNumber       = if ($bios) { $bios.SerialNumber } else { $null }
    DomainOrWorkgroup  = if ($computer) { $computer.Domain } else { $null }
    OperatingSystem    = if ($os) { $os.Caption } else { $null }
    OSVersion          = if ($os) { $os.Version } else { $null }
    OSBuild            = if ($os) { $os.BuildNumber } else { $null }
    InstallDate        = if ($os) { $os.InstallDate } else { $null }
    LastBootUpTime     = if ($os) { $os.LastBootUpTime } else { $null }
    Processor          = if ($processor -and $processor.Name) { $processor.Name.Trim() } else { $null }
    LogicalProcessors  = if ($computer) { $computer.NumberOfLogicalProcessors } else { $null }
    TotalMemory        = ConvertTo-ByteSize -Bytes $totalRam
    MemoryModules      = $memory.Count
    PendingReboot      = Test-PendingReboot -Target $ComputerName
    PowerShellVersion  = $PSVersionTable.PSVersion.ToString()
    PowerShellEdition  = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
    Disks              = $diskSummary
    NetworkAdapters    = $networkSummary
    Hotfixes           = $hotfixes
}

if ($OutputPath) {
    $exported = $inventory | Export-WinAutomateReport -Path $OutputPath
    Write-WinAutomateLog -Message "Inventory written to '$($exported.FullName)'." -LogPath $LogPath
}

Write-Output $inventory
