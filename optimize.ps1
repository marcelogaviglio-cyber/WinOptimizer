# Auto-elevate if not running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Start-Process $shell -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$global:WO_Root = $PSScriptRoot

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$global:WO_LogFile = Join-Path $logDir "optimize-$(Get-Date -Format 'yyyy-MM-dd').log"

. "$PSScriptRoot\modules\logger.ps1"
. "$PSScriptRoot\modules\reporter.ps1"
. "$PSScriptRoot\modules\backup.ps1"
. "$PSScriptRoot\modules\temp-cleaner.ps1"
. "$PSScriptRoot\modules\drivers.ps1"
. "$PSScriptRoot\modules\registry.ps1"
. "$PSScriptRoot\modules\hardware.ps1"

function Show-Menu {
    Clear-Host
    Write-Host "=== WinOptimizer ===" -ForegroundColor Cyan
    Write-Host "[1] Limpiar archivos temporales"
    Write-Host "[2] Actualizar drivers"
    Write-Host "[3] Registro — Nivel 1 Conservador"
    Write-Host "[4] Registro — Nivel 2 Moderado"
    Write-Host "[5] Registro — Nivel 3 Agresivo"
    Write-Host "[6] Aceleracion de hardware"
    Write-Host "[7] Ejecutar todo (opciones 1-6 en secuencia, sin pausas)"
    Write-Host "[0] Salir"
    Write-Host ""
    return (Read-Host "Seleccion").Trim()
}

Write-Log -Module "INIT" -Message "WinOptimizer iniciado"

do {
    $choice = Show-Menu
    switch ($choice) {
        "1" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Limpiar archivos temporales" -Items (Get-TempCleanerPreview) -Snapshot $snap) {
                $results = Invoke-TempCleaner -Interactive $true
                Write-Report -Title "Limpiar archivos temporales" -Results $results `
                    -OpSlug "temps" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "2" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Actualizar drivers" -Items (Get-DriverUpdatePreview) -Snapshot $snap) {
                $results = Invoke-DriverUpdate
                Write-Report -Title "Actualizar drivers" -Results $results `
                    -OpSlug "drivers" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "3" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Registro Nivel 1 Conservador" -Items (Get-RegistryPreview -Level 1) -Snapshot $snap) {
                $results = Invoke-RegistryFix -Level 1
                Write-Report -Title "Registro Nivel 1 Conservador" -Results $results `
                    -OpSlug "reg-L1" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "4" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Registro Nivel 2 Moderado" -Items (Get-RegistryPreview -Level 2) -Snapshot $snap) {
                $results = Invoke-RegistryFix -Level 2
                Write-Report -Title "Registro Nivel 2 Moderado" -Results $results `
                    -OpSlug "reg-L2" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "5" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Registro Nivel 3 Agresivo" -Items (Get-RegistryPreview -Level 3) -Snapshot $snap) {
                $results = Invoke-RegistryFix -Level 3
                Write-Report -Title "Registro Nivel 3 Agresivo" -Results $results `
                    -OpSlug "reg-L3" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "6" {
            $snap = Get-SystemSnapshot
            if (Show-Preview -Title "Aceleracion de hardware" -Items (Get-HardwarePreview) -Snapshot $snap) {
                $results = Invoke-HardwareOptimize
                Write-Report -Title "Aceleracion de hardware" -Results $results `
                    -OpSlug "hardware" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "7" {
            $snap = Get-SystemSnapshot
            $allItems = @(
                [PSCustomObject]@{ Label = "--- TEMPORALES ---"; Detail = "" }
            ) + (Get-TempCleanerPreview) + @(
                [PSCustomObject]@{ Label = "--- DRIVERS ---"; Detail = "" }
            ) + (Get-DriverUpdatePreview) + @(
                [PSCustomObject]@{ Label = "--- REGISTRO L1 ---"; Detail = "" }
            ) + (Get-RegistryPreview -Level 1) + @(
                [PSCustomObject]@{ Label = "--- REGISTRO L2 ---"; Detail = "" }
            ) + (Get-RegistryPreview -Level 2) + @(
                [PSCustomObject]@{ Label = "--- REGISTRO L3 ---"; Detail = "" }
            ) + (Get-RegistryPreview -Level 3) + @(
                [PSCustomObject]@{ Label = "--- HARDWARE ---"; Detail = "" }
            ) + (Get-HardwarePreview)

            if (Show-Preview -Title "Ejecutar todo" -Items $allItems -Snapshot $snap) {
                $allResults = @()
                $allResults += Invoke-TempCleaner -Interactive $false
                $allResults += Invoke-DriverUpdate
                $allResults += Invoke-RegistryFix -Level 1
                $allResults += Invoke-RegistryFix -Level 2
                $allResults += Invoke-RegistryFix -Level 3
                $allResults += Invoke-HardwareOptimize
                Write-Report -Title "Ejecutar todo" -Results $allResults `
                    -OpSlug "todo" -SnapshotAntes $snap -SnapshotDespues (Get-SystemSnapshot)
            }
        }
        "0" { Write-Log -Module "INIT" -Message "WinOptimizer finalizado" }
        default { Write-Host "Opcion invalida. Intenta de nuevo." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Write-Host "`nPresiona Enter para volver al menu..."
        [Console]::ReadKey($true) | Out-Null
    }
} while ($choice -ne "0")
