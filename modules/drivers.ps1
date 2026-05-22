function Invoke-DriverUpdate {
    Write-Log -Module "DRIVERS" -Message "Escaneando dispositivos..."

    $problematic = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Unknown", "Degraded") }

    if ($problematic.Count -eq 0) {
        Write-Log -Module "DRIVERS" -Message "No se detectaron dispositivos con problemas"
    } else {
        foreach ($dev in $problematic) {
            Write-Log -Module "DRIVERS" -Message "Dispositivo con problema: $($dev.FriendlyName) [$($dev.Status)]"
        }
    }

    Write-Log -Module "DRIVERS" -Message "Iniciando escaneo de drivers via Windows Update..."
    $scanOutput = & pnputil /scan-devices 2>&1
    Write-Log -Module "DRIVERS" -Message "pnputil: $($scanOutput -join ' ')"

    $updated = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "OK" -and $_.Present -eq $true }
    Write-Log -Module "DRIVERS" -Message "Escaneo completado. Dispositivos OK: $($updated.Count)"

    if ($problematic.Count -gt 0) {
        Write-Log -Module "DRIVERS" -Message "Dispositivos con problemas persistentes: $($problematic.Count) — revisar manualmente en Administrador de dispositivos"
    }
}
