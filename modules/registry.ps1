function Invoke-RegistryLevel1 {
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
}

function Invoke-RegistryLevel2 {
    $desktopPath = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desktopPath -Name "WaitToKillAppTimeout" -Value "5000" -Type String
    Set-ItemProperty -Path $desktopPath -Name "HungAppTimeout" -Value "3000" -Type String
    Write-Log -Module "REG-L2" -Message "Timeouts ajustados: WaitToKillApp=5000ms, HungApp=3000ms"

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
}

function Invoke-RegistryLevel3 {
    $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $mmcssPath) {
        Set-ItemProperty -Path $mmcssPath -Name "SystemResponsiveness" -Value 10 -Type DWord
        Set-ItemProperty -Path $mmcssPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
        Write-Log -Module "REG-L3" -Message "MMCSS: SystemResponsiveness=10, NetworkThrottlingIndex=max"
    }

    $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord
    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord
    Write-Log -Module "REG-L3" -Message "Memoria: LargeSystemCache=0, DisablePagingExecutive=1"

    $prefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq "0" }
    if ($disk -and $disk.MediaType -eq "SSD") {
        Set-ItemProperty -Path $prefetchPath -Name "EnablePrefetcher" -Value 0 -Type DWord
        Set-ItemProperty -Path $prefetchPath -Name "EnableSuperfetch" -Value 0 -Type DWord
        Write-Log -Module "REG-L3" -Message "Prefetch/Superfetch deshabilitado (SSD detectado)"
    } else {
        Write-Log -Module "REG-L3" -Message "Prefetch conservado (HDD detectado o disco no identificado)"
    }
}

function Invoke-RegistryFix {
    param([int]$Level)

    Write-Log -Module "REG-L$Level" -Message "Iniciando nivel $Level — creando backup..."
    New-RegistryBackup -Level "L$Level"

    switch ($Level) {
        1 { Invoke-RegistryLevel1 }
        2 { Invoke-RegistryLevel2 }
        3 { Invoke-RegistryLevel3 }
    }
}
