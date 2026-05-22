# WinOptimizer Reporter — Design Spec
**Date:** 2026-05-22
**Feature:** Preview + confirmación + reporte por operación

---

## Objetivo

Agregar a WinOptimizer un flujo de preview → confirmación → reporte para cada opción del menú. Antes de ejecutar, el usuario ve qué se va a hacer y confirma. Al terminar, se muestra un resumen de lo que ocurrió y se guarda en `reports\`.

---

## Criterio de éxito

- Cada opción del menú ([1]-[7]) muestra un preview antes de ejecutar
- El preview incluye snapshot del sistema (RAM libre, espacio en disco, plan de energía, drivers con problemas)
- El usuario puede cancelar con "n" sin que se ejecute nada
- Al finalizar cada operación se muestra un reporte con resultados reales
- El reporte incluye comparación antes/después de las métricas del sistema
- El reporte se guarda en `reports\reporte-YYYY-MM-DD-HHmm-[op].txt`

---

## Arquitectura

**Archivos nuevos:**
- `modules/reporter.ps1` — funciones de presentación: preview, confirmación, reporte
- `reports\` — directorio gitignored, un `.txt` por ejecución

**Archivos modificados:**
- `modules/temp-cleaner.ps1` — agrega `Get-TempCleanerPreview`
- `modules/drivers.ps1` — agrega `Get-DriverUpdatePreview`
- `modules/registry.ps1` — agrega `Get-RegistryPreview -Level [1|2|3]`
- `modules/hardware.ps1` — agrega `Get-HardwarePreview`
- `optimize.ps1` — envuelve cada opción con flujo preview → confirmar → ejecutar → reportar
- `.gitignore` — agrega `reports/`

---

## Flujo por operación

```
[usuario elige opción N]
       ↓
Get-SystemSnapshot → $snapAntes
       ↓
Get-*Preview → array de items pendientes
       ↓
Show-Preview -Title -Items -Snapshot $snapAntes → "¿Continuar? (s/n)"
       ↓ s                         ↓ n
Ejecutar módulo               Volver al menú (sin ejecutar nada)
       ↓
Get-SystemSnapshot → $snapDespues
       ↓
Recopilar resultados como array de ReportItems
       ↓
Write-Report -Title -Results -OpSlug -SnapshotAntes $snapAntes -SnapshotDespues $snapDespues
       ↓
consola + reports\reporte-*.txt
```

---

## modules/reporter.ps1

### Funciones públicas

**`Get-SystemSnapshot`**
Captura métricas del sistema en el momento de la llamada. Sin parámetros. Devuelve:
```powershell
[PSCustomObject]@{
    RAMLibreMB       = [int]          # MB de RAM física disponible
    DiscoLibreGB     = [float]        # GB libres en C:
    PlanEnergia      = [string]       # Nombre del plan activo
    DriversConError  = [int]          # Cantidad de dispositivos con estado Error/Unknown/Degraded
    Timestamp        = [datetime]     # Momento de la captura
}
```
Se llama una vez antes de ejecutar y una vez después. La diferencia se muestra en el reporte.

**`Show-Preview -Title [string] -Items [array] -Snapshot [PSCustomObject]`**
- Muestra encabezado `=== PREVIEW — $Title ===`
- Muestra sección "Estado actual del sistema" con el snapshot (RAM libre, disco libre, plan de energía, drivers con error)
- Lista cada item con etiqueta y detalle de lo que se va a hacer
- Pregunta `¿Continuar? (s/n)`
- Devuelve `$true` si el usuario escribe "s", `$false` para cualquier otra entrada

**`Write-Report -Title [string] -Results [array] -OpSlug [string] -SnapshotAntes [PSCustomObject] -SnapshotDespues [PSCustomObject]`**
- Muestra encabezado `=== REPORTE — $Title ===` con fecha/hora
- Lista cada resultado con ✓ (OK), ✗ (Error) o ⚠ (Skip)
- Muestra totales si el módulo los provee
- Muestra sección "Mejoras del sistema" comparando SnapshotAntes vs SnapshotDespues:
  - RAM libre: +X MB
  - Espacio en disco: +X GB
  - Plan de energía: Equilibrado → Alto Rendimiento
  - Drivers con error: N → M
- Crea `$global:WO_Root\reports\` si no existe
- Guarda en `reports\reporte-YYYY-MM-DD-HHmm-$OpSlug.txt`
- Loguea vía Write-Log la ruta del archivo guardado

**`New-ReportItem -Label [string] -Status [string] -Detail [string]`**
- Constructor de item de resultado
- Status: "OK" | "Skip" | "Error"
- Devuelve `[PSCustomObject]@{ Label; Status; Detail }`

---

## Datos de preview por módulo

### Get-TempCleanerPreview
Recorre los paths de sistema y browsers sin borrar nada.
Devuelve array de preview items: `{ Label = "C:\...\Temp"; Detail = "234 archivos (1.2 GB)" }`

### Get-DriverUpdatePreview
Ejecuta `Get-PnpDevice` para detectar dispositivos con estado Error/Unknown/Degraded.
Devuelve items: `{ Label = "Nombre dispositivo"; Detail = "[Estado]" }` o un item indicando "Sin problemas detectados".

### Get-RegistryPreview -Level [int]
- **L1:** escanea entradas huérfanas en Uninstall y Run keys sin borrarlas. Devuelve count + lista de nombres.
- **L2:** lee valores actuales de timeouts y lista qué paths MRU existen. Devuelve valores actuales → nuevos valores.
- **L3:** detecta tipo de disco (SSD/HDD), lee valores MMCSS y memoria actuales. Devuelve parámetros actuales → valores que se aplicarán.

### Get-HardwarePreview
Lee estado actual sin modificar nada:
- Plan de energía activo (`powercfg /getactivescheme`)
- Estado USB Selective Suspend (consulta powercfg)
- Valor actual de `Win32PrioritySeparation`
- Valor actual de `VisualFXSetting`

Devuelve items con formato `{ Label = "Plan de energía"; Detail = "Actual: Equilibrado → Nuevo: Alto Rendimiento" }`

---

## Formato de salida en consola

### Preview
```
=== PREVIEW — Limpiar archivos temporales ===

  Estado actual del sistema:
    RAM libre:          3.2 GB
    Espacio en disco:   45.8 GB libres en C:
    Plan de energía:    Equilibrado
    Drivers con error:  2

  Se BORRARÁN los siguientes archivos:
    • C:\Users\mgavi\AppData\Local\Temp    → 234 archivos (1.2 GB)
    • C:\Windows\Temp                      → 45 archivos (230 MB)
    • C:\Windows\SoftwareDistribution\...  → 12 archivos (89 MB)
    • Cache Edge                           → 89 archivos (450 MB)

  Se consultará confirmación para:
    • Papelera de reciclaje

¿Continuar? (s/n):
```

### Reporte
```
=== REPORTE — Limpiar archivos temporales ===
Fecha: 2026-05-22 10:32:15

  ✓ C:\Users\mgavi\AppData\Local\Temp    → 234 archivos eliminados (1.2 GB)
  ✓ C:\Windows\Temp                      → 45 archivos eliminados (230 MB)
  ✗ C:\Windows\SoftwareDistribution\...  → 3 archivos en uso (omitidos)
  ✓ Cache Edge                           → 89 archivos eliminados (450 MB)

  TOTAL: 1.65 GB liberados en 368 archivos

  Mejoras del sistema:
    RAM libre:          3.2 GB  →  3.4 GB   (+200 MB)
    Espacio en disco:   45.8 GB →  47.5 GB  (+1.65 GB)
    Plan de energía:    Equilibrado (sin cambios en esta operación)
    Drivers con error:  2 (sin cambios en esta operación)

Guardado en: reports\reporte-2026-05-22-1032-temps.txt
```

---

## Nombres de archivo de reporte

| Operación | Slug | Ejemplo |
|-----------|------|---------|
| Limpiar temporales | `temps` | `reporte-2026-05-22-1032-temps.txt` |
| Actualizar drivers | `drivers` | `reporte-2026-05-22-1045-drivers.txt` |
| Registro Nivel 1 | `reg-L1` | `reporte-2026-05-22-1050-reg-L1.txt` |
| Registro Nivel 2 | `reg-L2` | `reporte-2026-05-22-1051-reg-L2.txt` |
| Registro Nivel 3 | `reg-L3` | `reporte-2026-05-22-1052-reg-L3.txt` |
| Hardware | `hardware` | `reporte-2026-05-22-1055-hardware.txt` |

---

## Opción [7] Todo

Para la opción [7], el launcher llama a los 4 `Get-*Preview` en secuencia y muestra todos los resultados agrupados por sección en un único bloque antes de pedir confirmación. Una sola pregunta `¿Continuar? (s/n)` cubre todas las operaciones. Si el usuario confirma, ejecuta todo sin pausas adicionales. Al finalizar, consolida todos los resultados en un único archivo `reporte-YYYY-MM-DD-HHmm-todo.txt` y lo muestra en consola.

---

## Decisiones descartadas

| Opción | Razón de descarte |
|--------|-------------------|
| Retorno de objetos en cada módulo existente | Acopla lógica de display al launcher |
| Extender Write-Log con captura | Mezcla logging con reporting en un mismo módulo |
| Reporte solo en consola | El usuario pidió guardado explícitamente |
