function Get-DriverUpdatePreview {
    $problematic = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Unknown", "Degraded") }

    if ($problematic.Count -eq 0) {
        return @([PSCustomObject]@{
            Label  = "Estado de drivers"
            Detail = "No se detectaron dispositivos con problemas"
        })
    }

    $items = @()
    foreach ($dev in $problematic) {
        $items += [PSCustomObject]@{
            Label  = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.InstanceId }
            Detail = "Estado: $($dev.Status) — se intentara actualizar"
        }
    }
    return $items
}

function Invoke-DriverUpdate {
    $results = @()
    Write-Log -Module "DRIVERS" -Message "Escaneando dispositivos..."

    $problematic = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Unknown", "Degraded") }

    if ($problematic.Count -eq 0) {
        Write-Log -Module "DRIVERS" -Message "No se detectaron dispositivos con problemas"
        $results += [PSCustomObject]@{ Label = "Escaneo de dispositivos"; Status = "OK"; Detail = "Sin dispositivos con problemas" }
    } else {
        foreach ($dev in $problematic) {
            $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.InstanceId }
            Write-Log -Module "DRIVERS" -Message "Dispositivo con problema: $name [$($dev.Status)]"
            $results += [PSCustomObject]@{ Label = $name; Status = "Error"; Detail = "Estado: $($dev.Status)" }
        }
    }

    Write-Log -Module "DRIVERS" -Message "Iniciando escaneo de drivers via Windows Update..."
    $scanOutput = & pnputil /scan-devices 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Module "DRIVERS" -Message "[FALLO] pnputil fallo con codigo $LASTEXITCODE | $($scanOutput -join ' ')"
        $results += [PSCustomObject]@{ Label = "pnputil /scan-devices"; Status = "Error"; Detail = "Fallo con codigo $LASTEXITCODE" }
    } else {
        Write-Log -Module "DRIVERS" -Message "pnputil: $($scanOutput -join ' ')"
        $results += [PSCustomObject]@{ Label = "pnputil /scan-devices"; Status = "OK"; Detail = "Escaneo completado" }
    }

    $updated = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "OK" -and $_.Present -eq $true }
    Write-Log -Module "DRIVERS" -Message "Escaneo completado. Dispositivos OK: $($updated.Count)"

    return $results
}
