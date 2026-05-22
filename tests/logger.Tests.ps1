BeforeAll {
    $global:WO_LogFile = Join-Path $TestDrive "test-optimize.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
}

Describe "Write-Log" {
    It "writes a line with timestamp-module-message format to log file" {
        Write-Log -Module "TEST" -Message "mensaje de prueba"
        $content = Get-Content $global:WO_LogFile -Raw
        $content | Should -Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[TEST\] mensaje de prueba"
    }

    It "appends multiple lines without overwriting" {
        Write-Log -Module "A" -Message "linea 1"
        Write-Log -Module "B" -Message "linea 2"
        $lines = Get-Content $global:WO_LogFile
        $lines.Count | Should -BeGreaterOrEqual 2
    }
}
