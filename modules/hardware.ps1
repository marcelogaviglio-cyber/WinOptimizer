function Invoke-HardwareOptimize {
    $pcOutput = & powercfg /setactive SCHEME_MIN 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Module "HW" -Message "[FALLO] powercfg /setactive fallo | $($pcOutput -join ' ') | Verificar politicas de grupo"
    } else {
        Write-Log -Module "HW" -Message "Plan de energia: Alto Rendimiento activado"
    }

    & powercfg /SETACVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    & powercfg /SETDCVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "USB Selective Suspend: deshabilitado"

    $priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    Set-ItemProperty -Path $priorityPath -Name "Win32PrioritySeparation" -Value 38 -Type DWord
    Write-Log -Module "HW" -Message "Scheduling del procesador: favorece apps en primer plano"

    $visualPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualPath)) {
        New-Item -Path $visualPath -Force | Out-Null
    }
    Set-ItemProperty -Path $visualPath -Name "VisualFXSetting" -Value 2 -Type DWord
    Write-Log -Module "HW" -Message "Efectos visuales: mejor rendimiento"

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $ram = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { "?" }
    $pageFile = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue
    $pfSize = if ($pageFile) { "$($pageFile.AllocatedBaseSize) MB" } else { "no detectado" }
    Write-Log -Module "HW" -Message "RAM: ${ram} GB | Pagefile actual: $pfSize"

    & powercfg /update-settings 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "Configuracion de energia aplicada"
}
