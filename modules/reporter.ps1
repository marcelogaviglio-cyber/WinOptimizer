function Get-SystemSnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramMB = if ($os) { [int]($os.FreePhysicalMemory / 1KB) } else { 0 }

    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $discoGB = if ($drive) { [math]::Round($drive.Free / 1GB, 1) } else { 0.0 }

    $planOutput = & powercfg /getactivescheme 2>&1
    $planName = if ($planOutput -match '\((.+)\)') { $Matches[1] } else { "Desconocido" }

    $driversConError = (Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Degraded") } |
        Measure-Object).Count

    return [PSCustomObject]@{
        RAMLibreMB      = $ramMB
        DiscoLibreGB    = $discoGB
        PlanEnergia     = $planName
        DriversConError = $driversConError
        Timestamp       = Get-Date
    }
}

function New-ReportItem {
    param(
        [string]$Label,
        [ValidateSet("OK", "Skip", "Error")]
        [string]$Status,
        [string]$Detail
    )
    return [PSCustomObject]@{ Label = $Label; Status = $Status; Detail = $Detail }
}

function Show-Preview {
    param(
        [string]$Title,
        [array]$Items,
        [PSCustomObject]$Snapshot
    )

    $ramGB = [math]::Round($Snapshot.RAMLibreMB / 1KB, 1)

    Write-Host ""
    Write-Host "=== PREVIEW - $Title ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Estado actual del sistema:" -ForegroundColor Cyan
    Write-Host "    RAM libre:         $ramGB GB"
    Write-Host "    Espacio en disco:  $($Snapshot.DiscoLibreGB) GB libres en C:"
    Write-Host "    Plan de energia:   $($Snapshot.PlanEnergia)"
    Write-Host "    Drivers con error: $($Snapshot.DriversConError)"
    Write-Host ""

    if ($Items.Count -eq 0) {
        Write-Host "  Nada que hacer en esta operacion." -ForegroundColor Gray
    } else {
        Write-Host "  Acciones pendientes:" -ForegroundColor Cyan
        foreach ($item in $Items) {
            if ($item.Label -match '^---') {
                Write-Host ""
                Write-Host "  $($item.Label)" -ForegroundColor DarkCyan
            } else {
                Write-Host "    * $($item.Label)  ->  $($item.Detail)"
            }
        }
    }

    Write-Host ""
    $confirm = (Read-Host "Continuar? (s/n)").Trim().ToLower()
    return ($confirm -eq "s")
}

function Write-Report {
    param(
        [string]$Title,
        [array]$Results,
        [string]$OpSlug,
        [PSCustomObject]$SnapshotAntes,
        [PSCustomObject]$SnapshotDespues
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $dateSlug  = Get-Date -Format "yyyy-MM-dd-HHmm"

    $reportsDir = Join-Path $global:WO_Root "reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $reportFile = Join-Path $reportsDir "reporte-$dateSlug-$OpSlug.txt"

    $lines = @(
        "=== REPORTE - $Title ===",
        "Fecha: $timestamp",
        ""
    )

    foreach ($r in $Results) {
        $icon = switch ($r.Status) {
            "OK"    { "[OK]  " }
            "Skip"  { "[--]  " }
            "Error" { "[!!]  " }
            default { "[??]  " }
        }
        if ($r.Label -match '^---') {
            $lines += ""
            $lines += "  $($r.Label)"
        } else {
            $lines += "  $icon $($r.Label)  ->  $($r.Detail)"
        }
    }

    $ramAntesGB = [math]::Round($SnapshotAntes.RAMLibreMB / 1KB, 1)
    $ramDespGB  = [math]::Round($SnapshotDespues.RAMLibreMB / 1KB, 2)
    $ramDelta   = [math]::Round(($SnapshotDespues.RAMLibreMB - $SnapshotAntes.RAMLibreMB) / 1KB, 2)
    $diskDelta  = [math]::Round($SnapshotDespues.DiscoLibreGB - $SnapshotAntes.DiscoLibreGB, 2)

    $lines += ""
    $lines += "  Mejoras del sistema:"

    if ($ramDelta -ne 0) {
        $sign = if ($ramDelta -ge 0) { "+" } else { "" }
        $lines += "    RAM libre:         $ramAntesGB GB  ->  $ramDespGB GB  ($sign$ramDelta GB)"
    } else {
        $lines += "    RAM libre:         $ramAntesGB GB  (sin cambios en esta operacion)"
    }

    if ($diskDelta -ne 0) {
        $sign = if ($diskDelta -ge 0) { "+" } else { "" }
        $lines += "    Espacio en disco:  $($SnapshotAntes.DiscoLibreGB) GB  ->  $($SnapshotDespues.DiscoLibreGB) GB  ($sign$diskDelta GB)"
    } else {
        $lines += "    Espacio en disco:  $($SnapshotAntes.DiscoLibreGB) GB  (sin cambios en esta operacion)"
    }

    if ($SnapshotAntes.PlanEnergia -ne $SnapshotDespues.PlanEnergia) {
        $lines += "    Plan de energia:   $($SnapshotAntes.PlanEnergia)  ->  $($SnapshotDespues.PlanEnergia)"
    } else {
        $lines += "    Plan de energia:   $($SnapshotAntes.PlanEnergia)  (sin cambios en esta operacion)"
    }

    if ($SnapshotAntes.DriversConError -ne $SnapshotDespues.DriversConError) {
        $lines += "    Drivers con error: $($SnapshotAntes.DriversConError)  ->  $($SnapshotDespues.DriversConError)"
    } else {
        $lines += "    Drivers con error: $($SnapshotAntes.DriversConError)  (sin cambios en esta operacion)"
    }

    $lines += ""
    $lines += "Guardado en: reports\reporte-$dateSlug-$OpSlug.txt"

    Write-Host ""
    foreach ($line in $lines) {
        if     ($line -match "=== REPORTE")         { Write-Host $line -ForegroundColor Yellow }
        elseif ($line -match "Mejoras del sistema")  { Write-Host $line -ForegroundColor Cyan }
        elseif ($line -match "\[OK\]")               { Write-Host $line -ForegroundColor Green }
        elseif ($line -match "\[!!\]")               { Write-Host $line -ForegroundColor Red }
        elseif ($line -match "\[--\]")               { Write-Host $line -ForegroundColor Gray }
        else                                         { Write-Host $line }
    }

    $lines | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Log -Module "REPORT" -Message "Reporte guardado: reports\reporte-$dateSlug-$OpSlug.txt"
}
