function Get-RegistryPreview {
    param([int]$Level)

    $items = @()

    switch ($Level) {
        1 {
            $orphaned = 0
            $uninstallPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
            Get-ChildItem -Path $uninstallPath -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                $uninstallStr = $props.UninstallString
                if (-not $uninstallStr) { return }
                $exePath = $uninstallStr -replace '"([^"]+)".*', '$1'
                $exePath = $exePath -replace '^([^ ]+).*', '$1'
                if ($exePath -and -not (Test-Path $exePath)) { $orphaned++ }
            }
            $invalidRun = 0
            @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
              "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run") | ForEach-Object {
                $props = Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue
                if (-not $props) { return }
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    $exePath = $_.Value -replace '"([^"]+)".*', '$1'
                    $exePath = $exePath -replace '^([^ ]+).*', '$1'
                    if ($exePath -and -not (Test-Path $exePath)) { $invalidRun++ }
                }
            }
            $items += [PSCustomObject]@{ Label = "Entradas huerfanas en Uninstall"; Detail = "$orphaned encontradas — se eliminaran" }
            $items += [PSCustomObject]@{ Label = "Claves Run invalidas"; Detail = "$invalidRun encontradas — se eliminaran" }
        }
        2 {
            $desktopPath = "HKCU:\Control Panel\Desktop"
            $props = Get-ItemProperty -Path $desktopPath -ErrorAction SilentlyContinue
            $waitKill = if ($props -and $props.WaitToKillAppTimeout) { "$($props.WaitToKillAppTimeout) ms" } else { "20000 ms (default)" }
            $hung     = if ($props -and $props.HungAppTimeout) { "$($props.HungAppTimeout) ms" } else { "5000 ms (default)" }
            $items += [PSCustomObject]@{ Label = "WaitToKillAppTimeout"; Detail = "Actual: $waitKill  ->  Nuevo: 5000 ms" }
            $items += [PSCustomObject]@{ Label = "HungAppTimeout";       Detail = "Actual: $hung  ->  Nuevo: 3000 ms" }
            $mruPaths = @(
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
            )
            $mruCount = ($mruPaths | Where-Object { Test-Path $_ }).Count
            $items += [PSCustomObject]@{ Label = "Listas MRU"; Detail = "$mruCount rutas a limpiar" }
        }
        3 {
            $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq "0" }
            $diskType = if ($disk -and $disk.MediaType -eq "SSD") { "SSD" } else { "HDD" }
            $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            $mmcss = Get-ItemProperty -Path $mmcssPath -ErrorAction SilentlyContinue
            $sysResp = if ($mmcss -and $null -ne $mmcss.SystemResponsiveness) { $mmcss.SystemResponsiveness } else { "20 (default)" }
            $items += [PSCustomObject]@{ Label = "Disco detectado"; Detail = $diskType }
            $items += [PSCustomObject]@{ Label = "MMCSS SystemResponsiveness"; Detail = "Actual: $sysResp  ->  Nuevo: 10" }
            $items += [PSCustomObject]@{ Label = "DisablePagingExecutive"; Detail = "Se establecera en 1 (kernel en RAM)" }
            $prefetchMsg = if ($diskType -eq "SSD") { "Se deshabilitara (SSD)" } else { "Se conservara (HDD)" }
            $items += [PSCustomObject]@{ Label = "Prefetch/Superfetch"; Detail = $prefetchMsg }
        }
    }
    return $items
}

function Invoke-RegistryLevel1 {
    $results = @()
    $removed = 0

    $uninstallPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    Get-ChildItem -Path $uninstallPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $uninstallStr = $props.UninstallString
        if (-not $uninstallStr) { return }
        $exePath = $uninstallStr -replace '"([^"]+)".*', '$1'
        $exePath = $exePath -replace '^([^ ]+).*', '$1'
        if ($exePath -and -not (Test-Path $exePath)) {
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed++
            Write-Log -Module "REG-L1" -Message "Entrada huerfana eliminada: $($props.DisplayName ?? $_.PSChildName)"
        }
    }

    $runPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($runPath in $runPaths) {
        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties |
            Where-Object { $_.Name -notlike "PS*" } |
            ForEach-Object {
                $exePath = $_.Value -replace '"([^"]+)".*', '$1'
                $exePath = $exePath -replace '^([^ ]+).*', '$1'
                if ($exePath -and -not (Test-Path $exePath)) {
                    Remove-ItemProperty -Path $runPath -Name $_.Name -Force -ErrorAction SilentlyContinue
                    $removed++
                    Write-Log -Module "REG-L1" -Message "Clave Run invalida eliminada: $($_.Name)"
                }
            }
    }

    Write-Log -Module "REG-L1" -Message "Total: $removed entradas eliminadas"
    $results += [PSCustomObject]@{ Label = "Entradas de registro eliminadas"; Status = "OK"; Detail = "$removed entradas huerfanas o invalidas" }
    return $results
}

function Invoke-RegistryLevel2 {
    $results = @()

    $desktopPath = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desktopPath -Name "WaitToKillAppTimeout" -Value 5000 -Type DWord
    Set-ItemProperty -Path $desktopPath -Name "HungAppTimeout" -Value 3000 -Type DWord
    Write-Log -Module "REG-L2" -Message "Timeouts ajustados: WaitToKillApp=5000ms, HungApp=3000ms"
    $results += [PSCustomObject]@{ Label = "Timeouts del sistema"; Status = "OK"; Detail = "WaitToKillApp=5000ms, HungApp=3000ms" }

    $controlPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
    Set-ItemProperty -Path $controlPath -Name "WaitToKillServiceTimeout" -Value "5000" -Type String
    Write-Log -Module "REG-L2" -Message "WaitToKillServiceTimeout=5000ms"

    $mruPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
    )
    $cleaned = 0
    foreach ($path in $mruPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $cleaned++
            Write-Log -Module "REG-L2" -Message "MRU limpiado: $(Split-Path $path -Leaf)"
        }
    }
    Write-Log -Module "REG-L2" -Message "MRU: $cleaned rutas limpiadas"
    $results += [PSCustomObject]@{ Label = "Listas MRU"; Status = "OK"; Detail = "$cleaned rutas limpiadas" }
    return $results
}

function Invoke-RegistryLevel3 {
    $results = @()

    $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $mmcssPath) {
        Set-ItemProperty -Path $mmcssPath -Name "SystemResponsiveness" -Value 10 -Type DWord
        Set-ItemProperty -Path $mmcssPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
        Write-Log -Module "REG-L3" -Message "MMCSS: SystemResponsiveness=10, NetworkThrottlingIndex=max"
        $results += [PSCustomObject]@{ Label = "MMCSS"; Status = "OK"; Detail = "SystemResponsiveness=10, NetworkThrottlingIndex=max" }
    }

    $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord
    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord
    Write-Log -Module "REG-L3" -Message "Memoria: LargeSystemCache=0, DisablePagingExecutive=1"
    $results += [PSCustomObject]@{ Label = "Gestion de memoria"; Status = "OK"; Detail = "LargeSystemCache=0, DisablePagingExecutive=1" }

    $prefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq "0" }
    if ($disk -and $disk.MediaType -eq "SSD") {
        Set-ItemProperty -Path $prefetchPath -Name "EnablePrefetcher" -Value 0 -Type DWord
        Set-ItemProperty -Path $prefetchPath -Name "EnableSuperfetch" -Value 0 -Type DWord
        Write-Log -Module "REG-L3" -Message "Prefetch/Superfetch deshabilitado (SSD detectado)"
        $results += [PSCustomObject]@{ Label = "Prefetch/Superfetch"; Status = "OK"; Detail = "Deshabilitado (SSD detectado)" }
    } else {
        Write-Log -Module "REG-L3" -Message "Prefetch conservado (HDD detectado o disco no identificado)"
        $results += [PSCustomObject]@{ Label = "Prefetch/Superfetch"; Status = "Skip"; Detail = "Conservado (HDD o disco no identificado)" }
    }
    return $results
}

function Invoke-RegistryFix {
    param([int]$Level)

    if ($Level -notin @(1, 2, 3)) {
        throw "[FALLO] Nivel de registro invalido | Niveles validos: 1, 2, 3 | Recibido: $Level"
    }

    $results = @()
    Write-Log -Module "REG-L$Level" -Message "Iniciando nivel $Level — creando backup..."
    New-RegistryBackup -Level "L$Level"
    $results += [PSCustomObject]@{ Label = "Backup del registro L$Level"; Status = "OK"; Detail = "Guardado en backup\" }

    switch ($Level) {
        1 { $results += Invoke-RegistryLevel1 }
        2 { $results += Invoke-RegistryLevel2 }
        3 { $results += Invoke-RegistryLevel3 }
    }
    return $results
}
