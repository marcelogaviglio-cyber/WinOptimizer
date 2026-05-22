function Get-HardwarePreview {
    $items = @()

    $planOutput = & powercfg /getactivescheme 2>&1
    $planName = if ($planOutput -match '\((.+)\)') { $Matches[1] } else { "Desconocido" }
    $items += [PSCustomObject]@{ Label = "Plan de energia"; Detail = "Actual: $planName  ->  Nuevo: Alto Rendimiento" }

    $items += [PSCustomObject]@{ Label = "USB Selective Suspend"; Detail = "Se deshabilitara (AC y DC)" }

    $priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $currentPriority = (Get-ItemProperty -Path $priorityPath -ErrorAction SilentlyContinue).Win32PrioritySeparation
    $items += [PSCustomObject]@{
        Label  = "Win32PrioritySeparation"
        Detail = "Actual: $currentPriority  ->  Nuevo: 38 (favorece apps en primer plano)"
    }

    $visualPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $currentFX = (Get-ItemProperty -Path $visualPath -ErrorAction SilentlyContinue).VisualFXSetting
    $fxDesc = switch ($currentFX) {
        0 { "Personalizado" }; 1 { "Mejor apariencia" }
        2 { "Mejor rendimiento" }; 3 { "Dejar que Windows elija" }
        default { "No configurado" }
    }
    $items += [PSCustomObject]@{ Label = "Efectos visuales"; Detail = "Actual: $fxDesc  ->  Nuevo: Mejor rendimiento" }

    return $items
}

function Invoke-HardwareOptimize {
    $results = @()

    $pcOutput = & powercfg /setactive SCHEME_MIN 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Module "HW" -Message "[FALLO] powercfg /setactive fallo | $($pcOutput -join ' ') | Verificar politicas de grupo"
        $results += [PSCustomObject]@{ Label = "Plan de energia"; Status = "Error"; Detail = "Fallo: $($pcOutput -join ' ')" }
    } else {
        Write-Log -Module "HW" -Message "Plan de energia: Alto Rendimiento activado"
        $results += [PSCustomObject]@{ Label = "Plan de energia"; Status = "OK"; Detail = "Alto Rendimiento activado" }
    }

    & powercfg /SETACVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    & powercfg /SETDCVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "USB Selective Suspend: deshabilitado"
    $results += [PSCustomObject]@{ Label = "USB Selective Suspend"; Status = "OK"; Detail = "Deshabilitado" }

    $priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    Set-ItemProperty -Path $priorityPath -Name "Win32PrioritySeparation" -Value 38 -Type DWord
    Write-Log -Module "HW" -Message "Scheduling del procesador: favorece apps en primer plano"
    $results += [PSCustomObject]@{ Label = "Scheduling del procesador"; Status = "OK"; Detail = "Win32PrioritySeparation=38" }

    $visualPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualPath)) { New-Item -Path $visualPath -Force | Out-Null }
    Set-ItemProperty -Path $visualPath -Name "VisualFXSetting" -Value 2 -Type DWord
    Write-Log -Module "HW" -Message "Efectos visuales: mejor rendimiento"
    $results += [PSCustomObject]@{ Label = "Efectos visuales"; Status = "OK"; Detail = "VisualFXSetting=2 (mejor rendimiento)" }

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $ram = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { "?" }
    $pageFile = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue
    $pfSize = if ($pageFile) { "$($pageFile.AllocatedBaseSize) MB" } else { "no detectado" }
    Write-Log -Module "HW" -Message "RAM: ${ram} GB | Pagefile actual: $pfSize"
    $results += [PSCustomObject]@{ Label = "Memoria del sistema"; Status = "OK"; Detail = "RAM total: ${ram} GB | Pagefile: $pfSize" }

    & powercfg /update-settings 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "Configuracion de energia aplicada"
    return $results
}
