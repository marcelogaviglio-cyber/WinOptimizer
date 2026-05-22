function Get-DriverUpdatePreview {
    $realProblems = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Degraded") }

    $unknownCount = (Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Unknown" } | Measure-Object).Count

    $items = @()

    # Informacional: Unknown no implica error real
    if ($unknownCount -gt 0) {
        $items += [PSCustomObject]@{
            Label  = "Dispositivos con estado 'Unknown'"
            Detail = "$unknownCount encontrados — estado normal para dispositivos virtuales, se omiten"
        }
    }

    if ($realProblems.Count -eq 0) {
        $items += [PSCustomObject]@{
            Label  = "Dispositivos con error real (Error/Degraded)"
            Detail = "Ninguno — no se requiere accion"
        }
        return $items
    }

    # Advertencia de riesgos antes de listar dispositivos a reinstalar
    $items += [PSCustomObject]@{
        Label  = "ADVERTENCIA — Riesgos de reinstalacion de drivers"
        Detail = ""
    }
    $items += [PSCustomObject]@{
        Label  = "  Riesgo 1"
        Detail = "El dispositivo puede dejar de responder temporalmente durante la actualizacion"
    }
    $items += [PSCustomObject]@{
        Label  = "  Riesgo 2"
        Detail = "Puede requerirse reinicio del sistema para que el nuevo driver surta efecto"
    }
    $items += [PSCustomObject]@{
        Label  = "  Riesgo 3"
        Detail = "En casos raros, el nuevo driver puede ser incompatible — restaurar con Restaurar sistema si ocurre"
    }
    $items += [PSCustomObject]@{
        Label  = "  Riesgo 4"
        Detail = "Si el driver no esta en Windows Update, el intento fallara sin danos — es esperado"
    }

    $items += [PSCustomObject]@{
        Label  = "Dispositivos a reinstalar ($($realProblems.Count))"
        Detail = ""
    }
    foreach ($dev in $realProblems) {
        $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.InstanceId }
        $items += [PSCustomObject]@{
            Label  = "  $name"
            Detail = "Estado: $($dev.Status) — se intentara Update-PnpDevice"
        }
    }
    return $items
}

function Invoke-DriverUpdate {
    $results = @()
    Write-Log -Module "DRIVERS" -Message "Escaneando dispositivos..."

    # Solo Error y Degraded son problemas reales — Unknown es normal para dispositivos virtuales
    $realProblems = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Degraded") }

    $unknownCount = (Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Unknown" } | Measure-Object).Count

    if ($unknownCount -gt 0) {
        Write-Log -Module "DRIVERS" -Message "Dispositivos Unknown (virtuales, omitidos): $unknownCount"
        $results += [PSCustomObject]@{
            Label  = "Dispositivos Unknown omitidos"
            Status = "Skip"
            Detail = "$unknownCount dispositivos virtuales con estado normal — no requieren accion"
        }
    }

    if ($realProblems.Count -eq 0) {
        Write-Log -Module "DRIVERS" -Message "No se detectaron dispositivos con Error o Degraded"
        $results += [PSCustomObject]@{ Label = "Escaneo de dispositivos"; Status = "OK"; Detail = "Sin dispositivos con Error o Degraded" }
    } else {
        Write-Log -Module "DRIVERS" -Message "$($realProblems.Count) dispositivos con Error/Degraded — intentando actualizar..."

        foreach ($dev in $realProblems) {
            $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.InstanceId }
            Write-Log -Module "DRIVERS" -Message "Actualizando: $name [$($dev.Status)]"

            try {
                Import-Module PnpDevice -ErrorAction Stop
                Update-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop
                Write-Log -Module "DRIVERS" -Message "Actualizado: $name"
                $results += [PSCustomObject]@{
                    Label  = $name
                    Status = "OK"
                    Detail = "Driver actualizado correctamente"
                }
            } catch {
                $errMsg = $_.Exception.Message
                $detail = if ($errMsg -match "not recognized|no se reconoce") {
                    "Modulo PnpDevice no disponible en este sistema — instalar driver manualmente"
                } else {
                    "Sin driver disponible en Windows Update — instalar driver del fabricante"
                }
                Write-Log -Module "DRIVERS" -Message "No se pudo actualizar: $name | $errMsg"
                $results += [PSCustomObject]@{
                    Label  = $name
                    Status = "Skip"
                    Detail = $detail
                }
            }
        }
    }

    # Escaneo general para detectar actualizaciones pendientes
    Write-Log -Module "DRIVERS" -Message "Escaneo general via Windows Update..."
    $scanOutput = & pnputil /scan-devices 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Module "DRIVERS" -Message "[FALLO] pnputil fallo con codigo $LASTEXITCODE"
        $results += [PSCustomObject]@{ Label = "pnputil /scan-devices"; Status = "Error"; Detail = "Fallo con codigo $LASTEXITCODE" }
    } else {
        $results += [PSCustomObject]@{ Label = "pnputil /scan-devices"; Status = "OK"; Detail = "Escaneo completado" }
    }

    return $results
}
