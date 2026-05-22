BeforeAll {
    $global:WO_LogFile = Join-Path $TestDrive "test.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
    . "$PSScriptRoot\..\modules\temp-cleaner.ps1"
}

Describe "Get-BrowserCachePaths" {
    It "returns only paths that exist on disk" {
        $paths = Get-BrowserCachePaths
        foreach ($p in $paths) {
            Test-Path $p | Should -Be $true
        }
    }
}

Describe "Remove-DirectoryContents" {
    It "deletes files in a temp directory and returns correct count" {
        $dir = Join-Path $TestDrive "faketemp"
        New-Item -ItemType Directory -Path $dir | Out-Null
        New-Item -ItemType File -Path "$dir\a.tmp" | Out-Null
        New-Item -ItemType File -Path "$dir\b.tmp" | Out-Null

        $result = Remove-DirectoryContents -Path $dir
        $result.Files | Should -Be 2
        (Get-ChildItem $dir -File).Count | Should -Be 0
    }

    It "returns 0 files when directory does not exist" {
        $result = Remove-DirectoryContents -Path "C:\nonexistent\path\xyz123"
        $result.Files | Should -Be 0
    }
}
