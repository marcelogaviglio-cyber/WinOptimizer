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
    param([bool]$Interactive = $true)

    $results  = @()
    $totalFiles = 0
    $totalBytes = 0

    $sysPaths = @(
        @{ Label = "Temp usuario";         Path = $env:TEMP },
        @{ Label = "Temp Windows";         Path = "C:\Windows\Temp" },
        @{ Label = "Cache Windows Update"; Path = "C:\Windows\SoftwareDistribution\Download" },
        @{ Label = "Cache miniaturas";     Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
    )

    foreach ($p in $sysPaths) {
        $r = Remove-DirectoryContents -Path $p.Path
        $totalFiles += $r.Files; $totalBytes += $r.Bytes
        $sizeMB = [math]::Round($r.Bytes / 1MB, 1)
        $results += [PSCustomObject]@{
            Label  = $p.Label
            Status = "OK"
            Detail = "$($r.Files) archivos eliminados ($sizeMB MB)"
        }
        Write-Log -Module "TEMP" -Message "$($p.Path) — $($r.Files) archivos"
    }

    foreach ($path in (Get-BrowserCachePaths)) {
        $r = Remove-DirectoryContents -Path $path
        $totalFiles += $r.Files; $totalBytes += $r.Bytes
        $sizeMB = [math]::Round($r.Bytes / 1MB, 1)
        $results += [PSCustomObject]@{
            Label  = "Cache navegador"
            Status = "OK"
            Detail = "$($r.Files) archivos eliminados ($sizeMB MB)"
        }
        Write-Log -Module "TEMP" -Message "Cache navegador: $($r.Files) archivos"
    }

    if ($Interactive) {
        $confirm = Read-Host "Vaciar Papelera de reciclaje? (s/n)"
        if ($confirm -eq "s") {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            $results += [PSCustomObject]@{ Label = "Papelera de reciclaje"; Status = "OK"; Detail = "Vaciada" }
            Write-Log -Module "TEMP" -Message "Papelera vaciada"
        } else {
            $results += [PSCustomObject]@{ Label = "Papelera de reciclaje"; Status = "Skip"; Detail = "Omitida por el usuario" }
        }
    }

    $totalMB = [math]::Round($totalBytes / 1MB, 1)
    Write-Log -Module "TEMP" -Message "Total: ${totalMB} MB liberados en $totalFiles archivos"
    return $results
}

function Get-TempCleanerPreview {
    $items = @()

    $sysPaths = @(
        @{ Label = "Temp usuario";         Path = $env:TEMP },
        @{ Label = "Temp Windows";         Path = "C:\Windows\Temp" },
        @{ Label = "Cache Windows Update"; Path = "C:\Windows\SoftwareDistribution\Download" },
        @{ Label = "Cache miniaturas";     Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
    )

    foreach ($p in $sysPaths) {
        if (-not (Test-Path $p.Path)) { continue }
        $files = Get-ChildItem -Path $p.Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer }
        $count = ($files | Measure-Object).Count
        $sizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
        $items += [PSCustomObject]@{ Label = $p.Label; Detail = "$count archivos ($sizeMB MB)" }
    }

    foreach ($path in (Get-BrowserCachePaths)) {
        $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer }
        $count = ($files | Measure-Object).Count
        $sizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
        $items += [PSCustomObject]@{ Label = "Cache navegador"; Detail = "$count archivos ($sizeMB MB)" }
    }

    $items += [PSCustomObject]@{ Label = "Papelera de reciclaje"; Detail = "Se pedira confirmacion" }
    return $items
}
