Describe "New-RegistryBackup" {
    BeforeAll {
        $global:WO_Root = $TestDrive
        $global:WO_LogFile = Join-Path $TestDrive "test.log"
        . "$PSScriptRoot\..\modules\logger.ps1"
        . "$PSScriptRoot\..\modules\backup.ps1"
    }
    It "creates the backup directory if it does not exist" {
        Mock Invoke-RegExport { return @{ ExitCode = 0 } }
        New-RegistryBackup -Level "L1"
        Test-Path (Join-Path $TestDrive "backup") | Should Be $true
    }

    It "throws with [FALLO] prefix when export fails" {
        Mock Invoke-RegExport { return @{ ExitCode = 1 } }
        { New-RegistryBackup -Level "L1" } | Should Throw
    }

    It "returns backup file paths as array" {
        Mock Invoke-RegExport { return @{ ExitCode = 0 } }
        $result = New-RegistryBackup -Level "L1"
        $result | Should Not BeNullOrEmpty
    }
}
