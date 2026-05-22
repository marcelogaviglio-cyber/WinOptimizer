BeforeAll {
    $global:WO_Root = $TestDrive
    $global:WO_LogFile = Join-Path $TestDrive "test.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
    . "$PSScriptRoot\..\modules\reporter.ps1"
}

Describe "New-ReportItem" {
    It "returns object with Label, Status, Detail" {
        $item = New-ReportItem -Label "test" -Status "OK" -Detail "done"
        $item.Label  | Should -Be "test"
        $item.Status | Should -Be "OK"
        $item.Detail | Should -Be "done"
    }
}

Describe "Get-SystemSnapshot" {
    It "returns object with all required properties populated" {
        $snap = Get-SystemSnapshot
        $snap.RAMLibreMB      | Should -BeGreaterThan 0
        $snap.DiscoLibreGB    | Should -BeGreaterThan 0
        $snap.PlanEnergia     | Should -Not -BeNullOrEmpty
        $snap.DriversConError | Should -BeGreaterOrEqual 0
        $snap.Timestamp       | Should -Not -BeNullOrEmpty
    }
}

Describe "Show-Preview" {
    It "returns true when user confirms with s" {
        Mock Read-Host { return "s" }
        $snap = [PSCustomObject]@{
            RAMLibreMB = 4096; DiscoLibreGB = 50.0
            PlanEnergia = "Equilibrado"; DriversConError = 0
        }
        $items = @(New-ReportItem -Label "Archivo" -Status "OK" -Detail "detalle")
        $result = Show-Preview -Title "Test" -Items $items -Snapshot $snap
        $result | Should -Be $true
    }

    It "returns false when user enters anything other than s" {
        Mock Read-Host { return "n" }
        $snap = [PSCustomObject]@{
            RAMLibreMB = 4096; DiscoLibreGB = 50.0
            PlanEnergia = "Equilibrado"; DriversConError = 0
        }
        $result = Show-Preview -Title "Test" -Items @() -Snapshot $snap
        $result | Should -Be $false
    }
}

Describe "Write-Report" {
    It "creates a .txt file in the reports directory" {
        $snapA = [PSCustomObject]@{
            RAMLibreMB = 4000; DiscoLibreGB = 45.0
            PlanEnergia = "Equilibrado"; DriversConError = 2; Timestamp = Get-Date
        }
        $snapD = [PSCustomObject]@{
            RAMLibreMB = 4200; DiscoLibreGB = 46.5
            PlanEnergia = "Alto Rendimiento"; DriversConError = 1; Timestamp = Get-Date
        }
        $results = @(New-ReportItem -Label "C:\Temp" -Status "OK" -Detail "5 archivos")
        Write-Report -Title "Test" -Results $results -OpSlug "test" `
            -SnapshotAntes $snapA -SnapshotDespues $snapD
        $files = Get-ChildItem (Join-Path $TestDrive "reports") -Filter "*.txt" -ErrorAction SilentlyContinue
        $files.Count | Should -BeGreaterOrEqual 1
    }

    It "report file contains the operation title" {
        $snapA = [PSCustomObject]@{
            RAMLibreMB = 4000; DiscoLibreGB = 45.0
            PlanEnergia = "Equilibrado"; DriversConError = 0; Timestamp = Get-Date
        }
        $snapD = [PSCustomObject]@{
            RAMLibreMB = 4000; DiscoLibreGB = 45.0
            PlanEnergia = "Equilibrado"; DriversConError = 0; Timestamp = Get-Date
        }
        Write-Report -Title "MiOperacion" -Results @() -OpSlug "mio" `
            -SnapshotAntes $snapA -SnapshotDespues $snapD
        $file = Get-ChildItem (Join-Path $TestDrive "reports") -Filter "*-mio.txt" | Select-Object -Last 1
        $content = Get-Content $file.FullName -Raw
        $content | Should -Match "MiOperacion"
    }
}
