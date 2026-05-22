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
        "1" { Invoke-TempCleaner -Interactive $true }
        "2" { Invoke-DriverUpdate }
        "3" { Invoke-RegistryFix -Level 1 }
        "4" { Invoke-RegistryFix -Level 2 }
        "5" { Invoke-RegistryFix -Level 3 }
        "6" { Invoke-HardwareOptimize }
        "7" {
            Invoke-TempCleaner -Interactive $false
            Invoke-DriverUpdate
            Invoke-RegistryFix -Level 1
            Invoke-RegistryFix -Level 2
            Invoke-RegistryFix -Level 3
            Invoke-HardwareOptimize
        }
        "0" { Write-Log -Module "INIT" -Message "WinOptimizer finalizado" }
        default { Write-Host "Opcion invalida. Intenta de nuevo." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Write-Host "`nPresiona Enter para volver al menu..."
        [Console]::ReadKey($true) | Out-Null
    }
} while ($choice -ne "0")
