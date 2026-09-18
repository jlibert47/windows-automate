#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-WinAutomateRepoRoot {
    <#
    .SYNOPSIS
        Resolves the repository root from the installed WinAutomate.Common module path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # modules/WinAutomate.Common -> repo root
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function ConvertTo-ByteSize {
    <#
    .SYNOPSIS
        Converts a byte count into a human-readable size string.
    .PARAMETER Bytes
        Number of bytes. Null or negative values return N/A.
    .PARAMETER Precision
        Decimal places for units larger than bytes. Default is 2.
    .EXAMPLE
        ConvertTo-ByteSize -Bytes 1048576
        1.00 MB
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [Nullable[int64]]$Bytes,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$Precision = 2
    )

    process {
        if ($null -eq $Bytes -or $Bytes -lt 0) {
            return 'N/A'
        }

        $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
        $value = [double]$Bytes
        $unitIndex = 0

        while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
            $value = $value / 1024
            $unitIndex++
        }

        if ($unitIndex -eq 0) {
            return ('{0} {1}' -f $Bytes, $units[$unitIndex])
        }

        $formatted = $value.ToString("N$Precision", [System.Globalization.CultureInfo]::InvariantCulture)
        return ('{0} {1}' -f $formatted, $units[$unitIndex])
    }
}

function Test-ElevatedSession {
    <#
    .SYNOPSIS
        Returns $true when the current process is running as a Windows administrator.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Write-WinAutomateLog {
    <#
    .SYNOPSIS
        Writes a timestamped log line to the host and optionally to a file.
    .PARAMETER Message
        Log message text.
    .PARAMETER Level
        Severity: INFO, WARN, ERROR, or DEBUG.
    .PARAMETER LogPath
        Optional file path. Parent directories are created if missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    switch ($Level) {
        'WARN' { Write-Warning $Message }
        'ERROR' { Write-Error $Message -ErrorAction Continue }
        'DEBUG' { Write-Verbose $line }
        default { Write-Information $line -InformationAction Continue }
    }

    if ($LogPath) {
        $directory = Split-Path -Parent $LogPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
}

function Get-WinAutomateConfig {
    <#
    .SYNOPSIS
        Loads repository config from settings.json, falling back to settings.example.json.
    .PARAMETER Path
        Explicit config file path. When omitted, the repo config folder is used.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $configDir = Join-Path (Get-WinAutomateRepoRoot) 'config'
        $localPath = Join-Path $configDir 'settings.json'
        $examplePath = Join-Path $configDir 'settings.example.json'

        if (Test-Path -LiteralPath $localPath) {
            $Path = $localPath
        }
        else {
            $Path = $examplePath
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json)
}

function Export-WinAutomateReport {
    <#
    .SYNOPSIS
        Writes objects to CSV, JSON, or HTML based on the output path extension.
    .PARAMETER InputObject
        Objects to export. Accepts pipeline input.
    .PARAMETER Path
        Destination file path. Parent directories are created if missing.
    .PARAMETER Format
        Optional override. Inferred from the file extension when omitted.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Csv', 'Json', 'Html')]
        [string]$Format
    )

    begin {
        $items = New-Object System.Collections.Generic.List[object]

        if (-not $Format) {
            $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
            switch ($extension) {
                'csv' { $Format = 'Csv' }
                'html' { $Format = 'Html' }
                default { $Format = 'Json' }
            }
        }
    }

    process {
        if ($null -ne $InputObject) {
            [void]$items.Add($InputObject)
        }
    }

    end {
        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        switch ($Format) {
            'Csv' {
                $items | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
            }
            'Html' {
                $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $items |
                    ConvertTo-Html -Title 'WinAutomate Report' -PreContent "<h1>WinAutomate Report</h1><p>Generated $generated</p>" |
                    Set-Content -Path $Path -Encoding UTF8
            }
            default {
                $items | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
            }
        }

        return (Get-Item -LiteralPath $Path)
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-ByteSize',
    'Export-WinAutomateReport',
    'Get-WinAutomateConfig',
    'Get-WinAutomateRepoRoot',
    'Test-ElevatedSession',
    'Write-WinAutomateLog'
)
