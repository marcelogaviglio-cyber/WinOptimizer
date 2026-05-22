# WinOptimizer — Design Spec
**Date:** 2026-05-21
**Stack:** PowerShell (nativo Windows, cero dependencias externas)
**Ejecución:** A demanda, requiere elevación de Administrador

---

## Objetivo

App CLI en PowerShell para optimizar el rendimiento de una notebook Windows. Opera sobre cuatro dominios: limpieza de temporales, actualización de drivers, corrección del registro (3 niveles de riesgo escalables) y aceleración de hardware. Diseñada para consumo mínimo de RAM y cero instalación.

---

## Criterio de éxito

La ejecución completa (opción [7] Todo) debe:
1. Limpiar al menos los directorios temporales estándar de Windows sin errores fatales
2. Generar un backup `.reg` antes de cualquier modificación al registro
3. Producir un log legible con resultados y tamaño recuperado
4. No romper el sistema operativo en ningún nivel de riesgo

---

## Estructura del proyecto

```
WinOptimizer/
├── optimize.ps1              # Launcher + menú interactivo
├── modules/
│   ├── temp-cleaner.ps1      # Limpieza de temporales
│   ├── drivers.ps1           # Detección y actualización de drivers
│   ├── registry.ps1          # Corrección del registro (3 niveles)
│   └── hardware.ps1          # Aceleración de hardware
├── backup/                   # Auto-creado antes de cada cambio al registro
│   └── registry-YYYY-MM-DD-HH.reg
└── logs/
    └── optimize-YYYY-MM-DD.log
```

---

## Menú interactivo (optimize.ps1)

```
=== WinOptimizer ===
[1] Limpiar archivos temporales
[2] Actualizar drivers
[3] Registro — Nivel 1 Conservador
[4] Registro — Nivel 2 Moderado
[5] Registro — Nivel 3 Agresivo
[6] Aceleración de hardware
[7] Ejecutar todo (opciones 1-6 en secuencia, sin pausas)
[0] Salir
```

El launcher verifica elevación al inicio. Si no es Administrador, relanza con `Start-Process -Verb RunAs` automáticamente.

---

## Módulos

### temp-cleaner.ps1
Limpia en orden:
- `%TEMP%` (perfil de usuario)
- `C:\Windows\Temp`
- `C:\Windows\SoftwareDistribution\Download` (caché de Windows Update)
- Caché de miniaturas (`%LOCALAPPDATA%\Microsoft\Windows\Explorer`)
- Papelera de reciclaje (confirmación explícita en modo interactivo; se skipea en modo [7] Todo)
- Cachés de Chrome, Edge y Firefox — solo si el proceso no está en ejecución

Archivos en uso: se skipean sin error fatal, se loguean.

### drivers.ps1
1. `Get-PnpDevice` — lista dispositivos con estado de error o sin driver
2. `pnputil /scan-devices` — fuerza búsqueda en Windows Update
3. Reporta: drivers actualizados, drivers que requieren acción manual con nombre de dispositivo

No descarga drivers de terceros. Solo fuentes validadas por Microsoft.

### registry.ps1

**Antes de cualquier nivel:** exporta backup `.reg` de las claves a modificar en `backup/`. Si el backup falla, el módulo se aborta.

**Nivel 1 — Conservador**
- Entradas huérfanas en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
- Asociaciones de archivos apuntando a ejecutables inexistentes
- Claves `Run`/`RunOnce` con rutas inválidas

**Nivel 2 — Moderado**
- Ajuste de timeouts del sistema (`WaitToKillServiceTimeout`, `HungAppTimeout`)
- Limpieza de listas MRU (Most Recently Used) en Explorer y aplicaciones
- Delay de inicio de servicios no críticos
- Claves de startup de programas ya desinstalados

**Nivel 3 — Agresivo**
- Parámetros MMCSS (Multimedia Class Scheduler Service)
- Configuración de memoria: `LargeSystemCache`, `IoPageLockLimit`
- Prefetch y Superfetch: ajuste según tipo de almacenamiento (HDD vs SSD)
- Prioridad de IRQ para dispositivos de red y almacenamiento

### hardware.ps1
- Establece plan de energía en Alto Rendimiento (`powercfg /setactive SCHEME_MIN`)
- Deshabilita USB Selective Suspend
- Ajusta scheduling del procesador: `Win32PrioritySeparation` → favorece aplicaciones en primer plano
- Desactiva efectos visuales superfluos (animaciones, transparencias)
- Verifica configuración de memoria virtual: reporta si es subóptima, propone ajuste

---

## Logging

Formato por línea:
```
[YYYY-MM-DD HH:mm:ss] [MODULO] Descripción del resultado
```

Ejemplo:
```
[2026-05-21 10:32:01] [TEMP]     Eliminados 1.4 GB en 3,842 archivos
[2026-05-21 10:32:15] [DRIVERS]  3 drivers actualizados, 1 requiere acción manual
[2026-05-21 10:32:45] [REG-L1]   47 claves huérfanas eliminadas
[2026-05-21 10:32:46] [BACKUP]   Guardado en backup/registry-2026-05-21-10.reg
[2026-05-21 10:33:10] [HW]       Plan de energía: Alto Rendimiento activado
```

---

## Manejo de errores

- Cada módulo usa `try/catch` — nunca fallo silencioso
- Formato de fallo: `[FALLO] <qué falló> | <impacto> | <qué se necesita>`
- Si un módulo falla, los restantes continúan
- Archivos en uso: skip + log, no error fatal
- Sin backup exitoso: registry.ps1 se aborta completamente

---

## Decisiones descartadas

| Opción | Razón de descarte |
|--------|-------------------|
| GUI (WinForms/tkinter) | Overhead de RAM innecesario para uso a demanda |
| Python | Intérprete pesa ~30 MB; PowerShell ya está instalado |
| Rust | Tiempo de desarrollo desproporcionado para scripts de mantenimiento |
| Winget para drivers | Dependencia de publicación de fabricantes; pnputil usa fuentes validadas por MS |
| Config JSON | Innecesario para uso a demanda; el menú interactivo cubre el caso |
| Script único | No escalable para 3 niveles de registro + módulos independientes |
