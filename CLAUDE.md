# WinOptimizer

## Stack
PowerShell 5.1+ (nativo Windows), Pester v5 para tests

## Estructura
- optimize.ps1 — launcher + menú
- modules/ — 6 módulos independientes (logger, backup, temp-cleaner, drivers, registry, hardware)
- tests/ — Pester tests para módulos lógicos
- logs/ — un log por día (gitignored)
- backup/ — backups .reg pre-registro (gitignored)

## Comandos clave
- Ejecutar: `pwsh -File optimize.ps1` (requiere Administrador)
- Tests: `Invoke-Pester -Path tests\ -Output Detailed`
- Log de hoy: `Get-Content logs\optimize-$(Get-Date -Format 'yyyy-MM-dd').log`

## Próxima acción
Mantenimiento: agregar nuevos paths en temp-cleaner.ps1 > $sysPaths si se detectan nuevas fuentes de temporales.

## Historial de decisiones
- Stack PowerShell: nativo Windows, sin instalación, acceso directo a WMI y registro
- CLI sin GUI: mínimo RAM, uso a demanda
- Backup obligatorio antes de registro: seguridad no negociable en L1/L2/L3
- pnputil para drivers: fuentes validadas por Microsoft, sin riesgo de driver incompatible
- Niveles de registro escalables: usuario elige el riesgo aceptable
