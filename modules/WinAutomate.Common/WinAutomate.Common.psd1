@{
    RootModule           = 'WinAutomate.Common.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '7e4c1a90-2b8f-4d3e-9a6c-5f1d8e2b4c70'
    Author               = 'windows-automate contributors'
    CompanyName          = 'windows-automate'
    Copyright            = '(c) windows-automate contributors. All rights reserved.'
    Description          = 'Shared helpers for Windows PowerShell automation scripts in this repository.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'ConvertTo-ByteSize',
        'Export-WinAutomateReport',
        'Get-WinAutomateConfig',
        'Get-WinAutomateRepoRoot',
        'Test-ElevatedSession',
        'Write-WinAutomateLog'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'Automation', 'PowerShell')
            ProjectUri = 'https://github.com/jlibert47/windows-automate'
        }
    }
}
