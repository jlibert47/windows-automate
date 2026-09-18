#Requires -Version 5.1
# These tests target Pester 5. Run:  .\tests\Invoke-Tests.ps1
# If Pester is missing, that wrapper prints the Install-Module command and exits.

BeforeAll {
    $manifest = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules') 'WinAutomate.Common') 'WinAutomate.Common.psd1'
    Import-Module $manifest -Force
}

Describe 'ConvertTo-ByteSize' {
    It 'formats a byte count without a decimal' {
        ConvertTo-ByteSize -Bytes 512 | Should -Be '512 B'
    }

    It 'formats kibibytes with two decimal places' {
        ConvertTo-ByteSize -Bytes 2048 | Should -Be '2.00 KB'
    }

    It 'formats mebibytes' {
        ConvertTo-ByteSize -Bytes 1048576 | Should -Be '1.00 MB'
    }

    It 'formats gibibytes' {
        ConvertTo-ByteSize -Bytes 1073741824 | Should -Be '1.00 GB'
    }

    It 'returns N/A for null input' {
        ConvertTo-ByteSize -Bytes $null | Should -Be 'N/A'
    }

    It 'returns N/A for negative input' {
        ConvertTo-ByteSize -Bytes -1 | Should -Be 'N/A'
    }
}

Describe 'Get-WinAutomateConfig' {
    It 'loads the example config when no local settings.json exists' {
        $config = Get-WinAutomateConfig
        $config.diskSpace.warningPercentFree | Should -Be 15
        $config.tempCleanup.olderThanDays | Should -Be 7
    }

    It 'loads an explicit config file path' {
        $example = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'config') 'settings.example.json'
        $config = Get-WinAutomateConfig -Path $example
        $config.defaultOutputDirectory | Should -Be 'output'
    }
}

Describe 'Test-ElevatedSession' {
    It 'returns a boolean' {
        Test-ElevatedSession | Should -BeOfType [bool]
    }
}

Describe 'Starter scripts' {
    BeforeAll {
        $script:scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $script:scripts = @(Get-ChildItem -LiteralPath $script:scriptDir -Filter *.ps1)
    }

    It 'includes at least three runnable scripts' {
        $script:scripts.Count | Should -BeGreaterOrEqual 3
    }

    It '<Name> has comment-based help with a synopsis' -TestCases @(
        @{ Name = 'Get-MachineInventory.ps1' }
        @{ Name = 'Get-DiskSpaceReport.ps1' }
        @{ Name = 'Clear-TempFiles.ps1' }
    ) {
        param($Name)
        $path = Join-Path $script:scriptDir $Name
        $help = Get-Help $path -ErrorAction Stop
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match 'not found'
    }
}
