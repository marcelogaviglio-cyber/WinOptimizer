function Get-BrowserCachePaths {
    <#
    .SYNOPSIS
    Returns browser cache paths only if the browser process is not running.

    .OUTPUTS
    [string[]] Array of valid cache paths
    #>
    $candidates = @(
        @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Process = "chrome" },
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Process = "msedge" },
        @{ Path = "$env:APPDATA\Mozilla\Firefox\Profiles"; Process = "firefox"; IsProfileDir = $true }
    )

    $result = @()
    foreach ($c in $candidates) {
        if (-not (Test-Path $c.Path)) { continue }
        if (Get-Process -Name $c.Process -ErrorAction SilentlyContinue) { continue }

        if ($c.IsProfileDir) {
            Get-ChildItem $c.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $cachePath = Join-Path $_.FullName "cache2"
                if (Test-Path $cachePath) { $result += $cachePath }
            }
        } else {
            $result += $c.Path
        }
    }
    return $result
}

function Remove-DirectoryContents {
    <#
    .SYNOPSIS
    Recursively deletes files in a directory, skipping locked files.

    .PARAMETER Path
    Directory path to clean

    .OUTPUTS
    [PSCustomObject] with properties: Files (count), Bytes (total size deleted)
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{ Files = 0; Bytes = 0 }
    }

    $count = 0
    $size = 0

    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            $size += $_.Length
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                $count++
            } catch {
                Write-Log -Module "TEMP" -Message "Skip (en uso): $($_.Name)"
            }
        }

    return [PSCustomObject]@{ Files = $count; Bytes = $size }
}

function Invoke-TempCleaner {
    <#
    .SYNOPSIS
    Orchestrates cleanup of system temp directories and browser caches.

    .PARAMETER Interactive
    If $true, prompts user to empty Recycle Bin. If $false, skips the prompt.
    Default: $true

    .OUTPUTS
    None (logs results via Write-Log)
    #>
    param([bool]$Interactive = $true)

    $totalFiles = 0
    $totalBytes = 0

    # System temp paths
    $sysPaths = @(
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Windows\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    )

    foreach ($path in $sysPaths) {
        $result = Remove-DirectoryContents -Path $path
        $totalFiles += $result.Files
        $totalBytes += $result.Bytes
        Write-Log -Module "TEMP" -Message "$path — $($result.Files) archivos"
    }

    # Browser caches
    foreach ($path in (Get-BrowserCachePaths)) {
        $result = Remove-DirectoryContents -Path $path
        $totalFiles += $result.Files
        $totalBytes += $result.Bytes
        Write-Log -Module "TEMP" -Message "Cache navegador: $($result.Files) archivos"
    }

    # Recycle bin (interactive only)
    if ($Interactive) {
        $confirm = Read-Host "Vaciar Papelera de reciclaje? (s/n)"
        if ($confirm -eq "s") {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log -Module "TEMP" -Message "Papelera vaciada"
        }
    }

    # Summary
    $totalMB = [math]::Round($totalBytes / 1MB, 1)
    Write-Log -Module "TEMP" -Message "Total: ${totalMB} MB liberados en $totalFiles archivos"
}
