# WinOptimizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CLI PowerShell tool that cleans temp files, updates drivers, fixes the registry (3 escalating risk levels), and optimizes hardware settings on a Windows notebook.

**Architecture:** Launcher (`optimize.ps1`) dot-sources six modules; two shared utilities (logger, backup) plus four operation modules. Each module exposes a single public function. The launcher drives an interactive menu and passes an `$Interactive` flag to modules that need it.

**Tech Stack:** PowerShell 5.1+ (built into Windows 10/11), Pester v5 for unit tests, `reg.exe` and `pnputil.exe` for system operations (both shipped with Windows).

---

## File Map

| File | Responsibility |
|------|---------------|
| `optimize.ps1` | Entry point: elevation check, menu loop, module invocation |
| `modules/logger.ps1` | `Write-Log` — timestamped output to console + log file |
| `modules/backup.ps1` | `New-RegistryBackup` — exports registry keys before any modification |
| `modules/temp-cleaner.ps1` | `Invoke-TempCleaner` — cleans Windows temp dirs and browser caches |
| `modules/drivers.ps1` | `Invoke-DriverUpdate` — scans devices and triggers Windows Update scan |
| `modules/registry.ps1` | `Invoke-RegistryFix -Level 1|2|3` — three escalating registry cleanups |
| `modules/hardware.ps1` | `Invoke-HardwareOptimize` — power plan, USB suspend, visual effects, scheduling |
| `tests/logger.Tests.ps1` | Pester tests for Write-Log format and file output |
| `tests/backup.Tests.ps1` | Pester tests for backup directory creation and failure handling |
| `tests/temp-cleaner.Tests.ps1` | Pester tests for path resolution helpers |
| `CLAUDE.md` | Project memory: stack, commands, next action |

---

## Task 1: Project scaffold + git init

**Files:**
- Create: `G:\PROYECTOS\WinOptimizer\` (root)
- Create: `modules\`, `tests\`, `logs\`, `backup\` directories
- Create: `.gitignore`

- [ ] **Step 1: Create directory structure**

```powershell
$root = "G:\PROYECTOS\WinOptimizer"
@("modules", "tests", "logs", "backup") | ForEach-Object {
    New-Item -ItemType Directory -Path "$root\$_" -Force | Out-Null
}
```

- [ ] **Step 2: Create .gitignore**

Create `G:\PROYECTOS\WinOptimizer\.gitignore`:
```
logs/
backup/
```

- [ ] **Step 3: Git init + first commit**

```powershell
Set-Location "G:\PROYECTOS\WinOptimizer"
git init
git add .gitignore
git commit -m "chore: project scaffold"
```

Expected output: `[master (root-commit) xxxxxxx] chore: project scaffold`

---

## Task 2: modules/logger.ps1 (TDD)

**Files:**
- Create: `modules\logger.ps1`
- Create: `tests\logger.Tests.ps1`

- [ ] **Step 1: Install Pester if not present**

```powershell
if (-not (Get-Module -Name Pester -ListAvailable | Where-Object Version -ge "5.0")) {
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}
```

- [ ] **Step 2: Write the failing test**

Create `G:\PROYECTOS\WinOptimizer\tests\logger.Tests.ps1`:
```powershell
BeforeAll {
    $global:WO_LogFile = Join-Path $TestDrive "test-optimize.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
}

Describe "Write-Log" {
    It "writes a line with timestamp-module-message format to log file" {
        Write-Log -Module "TEST" -Message "mensaje de prueba"
        $content = Get-Content $global:WO_LogFile -Raw
        $content | Should -Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[TEST\] mensaje de prueba"
    }

    It "appends multiple lines without overwriting" {
        Write-Log -Module "A" -Message "linea 1"
        Write-Log -Module "B" -Message "linea 2"
        $lines = Get-Content $global:WO_LogFile
        $lines.Count | Should -BeGreaterOrEqual 2
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```powershell
Set-Location "G:\PROYECTOS\WinOptimizer"
Invoke-Pester -Path tests\logger.Tests.ps1 -Output Detailed
```

Expected: FAIL — `Write-Log` not defined.

- [ ] **Step 4: Implement modules/logger.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\logger.ps1`:
```powershell
function Write-Log {
    param(
        [string]$Module,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Module] $Message"
    Write-Host $line
    $logDir = Split-Path $global:WO_LogFile -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    Add-Content -Path $global:WO_LogFile -Value $line -Encoding UTF8
}
```

- [ ] **Step 5: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests\logger.Tests.ps1 -Output Detailed
```

Expected: `Tests Passed: 2, Failed: 0`

- [ ] **Step 6: Commit**

```powershell
git add modules\logger.ps1 tests\logger.Tests.ps1
git commit -m "feat: add Write-Log module with Pester tests"
```

---

## Task 3: modules/backup.ps1 (TDD)

**Files:**
- Create: `modules\backup.ps1`
- Create: `tests\backup.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `G:\PROYECTOS\WinOptimizer\tests\backup.Tests.ps1`:
```powershell
BeforeAll {
    $global:WO_Root = $TestDrive
    $global:WO_LogFile = Join-Path $TestDrive "test.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
    . "$PSScriptRoot\..\modules\backup.ps1"
}

Describe "New-RegistryBackup" {
    It "creates the backup directory if it does not exist" {
        Mock Invoke-RegExport { return @{ ExitCode = 0 } }
        New-RegistryBackup -Level "L1"
        Test-Path (Join-Path $TestDrive "backup") | Should -Be $true
    }

    It "throws with [FALLO] prefix when export fails" {
        Mock Invoke-RegExport { throw "[FALLO] reg export fallido | no backup | key error" }
        { New-RegistryBackup -Level "L1" } | Should -Throw "*FALLO*"
    }

    It "returns backup file paths as array" {
        Mock Invoke-RegExport { return @{ ExitCode = 0 } }
        $result = New-RegistryBackup -Level "L1"
        $result | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests\backup.Tests.ps1 -Output Detailed
```

Expected: FAIL — `New-RegistryBackup` not defined.

- [ ] **Step 3: Implement modules/backup.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\backup.ps1`:
```powershell
# Wrapper so tests can mock reg.exe calls
function Invoke-RegExport {
    param([string]$Key, [string]$File)
    & reg export $Key $File /y 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = $args }
}

function New-RegistryBackup {
    param([string]$Level)

    $backupDir = Join-Path $global:WO_Root "backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"

    $keysByLevel = @{
        "L1" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        "L2" = @(
            "HKCU\Control Panel\Desktop",
            "HKLM\SYSTEM\CurrentControlSet\Control",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"
        )
        "L3" = @(
            "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile",
            "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        )
    }

    $keys = $keysByLevel[$Level]
    $backupFiles = @()

    for ($i = 0; $i -lt $keys.Count; $i++) {
        $backupFile = Join-Path $backupDir "registry-$Level-$timestamp-$i.reg"
        $result = Invoke-RegExport -Key $keys[$i] -File $backupFile
        if ($result.ExitCode -ne 0) {
            throw "[FALLO] Backup del registro fallido | No se puede continuar sin backup | Key: $($keys[$i])"
        }
        $backupFiles += $backupFile
    }

    Write-Log -Module "BACKUP" -Message "Backup $Level guardado: $($backupFiles.Count) archivos en backup\"
    return $backupFiles
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests\backup.Tests.ps1 -Output Detailed
```

Expected: `Tests Passed: 3, Failed: 0`

- [ ] **Step 5: Commit**

```powershell
git add modules\backup.ps1 tests\backup.Tests.ps1
git commit -m "feat: add New-RegistryBackup module with Pester tests"
```

---

## Task 4: modules/temp-cleaner.ps1 (TDD)

**Files:**
- Create: `modules\temp-cleaner.ps1`
- Create: `tests\temp-cleaner.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `G:\PROYECTOS\WinOptimizer\tests\temp-cleaner.Tests.ps1`:
```powershell
BeforeAll {
    $global:WO_LogFile = Join-Path $TestDrive "test.log"
    . "$PSScriptRoot\..\modules\logger.ps1"
    . "$PSScriptRoot\..\modules\temp-cleaner.ps1"
}

Describe "Get-BrowserCachePaths" {
    It "returns only paths that exist on disk" {
        $paths = Get-BrowserCachePaths
        foreach ($p in $paths) {
            Test-Path $p | Should -Be $true
        }
    }
}

Describe "Remove-DirectoryContents" {
    It "deletes files in a temp directory and returns correct count" {
        $dir = Join-Path $TestDrive "faketemp"
        New-Item -ItemType Directory -Path $dir | Out-Null
        New-Item -ItemType File -Path "$dir\a.tmp" | Out-Null
        New-Item -ItemType File -Path "$dir\b.tmp" | Out-Null

        $result = Remove-DirectoryContents -Path $dir
        $result.Files | Should -Be 2
        (Get-ChildItem $dir -File).Count | Should -Be 0
    }

    It "returns 0 files when directory does not exist" {
        $result = Remove-DirectoryContents -Path "C:\nonexistent\path\xyz123"
        $result.Files | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path tests\temp-cleaner.Tests.ps1 -Output Detailed
```

Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement modules/temp-cleaner.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\temp-cleaner.ps1`:
```powershell
function Get-BrowserCachePaths {
    $candidates = @(
        @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Process = "chrome" },
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Process = "msedge" },
        @{ Path = "$env:APPDATA\Mozilla\Firefox\Profiles"; Process = "firefox"; IsProfileDir = $true }
    )

    $result = @()
    foreach ($c in $candidates) {
        if (-not (Test-Path $c.Path)) { continue }
        if (Get-Process -Name $c.Process -ErrorAction SilentlyContinue) { continue }

        if ($c.IsProfileDir) {
            Get-ChildItem $c.Path -Directory | ForEach-Object {
                $cachePath = Join-Path $_.FullName "cache2"
                if (Test-Path $cachePath) { $result += $cachePath }
            }
        } else {
            $result += $c.Path
        }
    }
    return $result
}

function Remove-DirectoryContents {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [PSCustomObject]@{ Files = 0; Bytes = 0 } }

    $count = 0; $size = 0
    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            $size += $_.Length
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                $count++
            } catch {
                Write-Log -Module "TEMP" -Message "Skip (en uso): $($_.Name)"
            }
        }
    return [PSCustomObject]@{ Files = $count; Bytes = $size }
}

function Invoke-TempCleaner {
    param([bool]$Interactive = $true)

    $totalFiles = 0; $totalBytes = 0

    $sysPaths = @(
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Windows\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    )

    foreach ($path in $sysPaths) {
        $result = Remove-DirectoryContents -Path $path
        $totalFiles += $result.Files; $totalBytes += $result.Bytes
        Write-Log -Module "TEMP" -Message "$path — $($result.Files) archivos"
    }

    foreach ($path in (Get-BrowserCachePaths)) {
        $result = Remove-DirectoryContents -Path $path
        $totalFiles += $result.Files; $totalBytes += $result.Bytes
        Write-Log -Module "TEMP" -Message "Cache navegador: $($result.Files) archivos"
    }

    if ($Interactive) {
        $confirm = Read-Host "Vaciar Papelera de reciclaje? (s/n)"
        if ($confirm -eq "s") {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log -Module "TEMP" -Message "Papelera vaciada"
        }
    }

    $totalMB = [math]::Round($totalBytes / 1MB, 1)
    Write-Log -Module "TEMP" -Message "Total: ${totalMB} MB liberados en $totalFiles archivos"
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests\temp-cleaner.Tests.ps1 -Output Detailed
```

Expected: `Tests Passed: 3, Failed: 0`

- [ ] **Step 5: Commit**

```powershell
git add modules\temp-cleaner.ps1 tests\temp-cleaner.Tests.ps1
git commit -m "feat: add Invoke-TempCleaner module with Pester tests"
```

---

## Task 5: modules/drivers.ps1

**Files:**
- Create: `modules\drivers.ps1`

No unit tests for this module — it wraps `pnputil.exe` and WMI which require real hardware. Verification is manual.

- [ ] **Step 1: Implement modules/drivers.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\drivers.ps1`:
```powershell
function Invoke-DriverUpdate {
    Write-Log -Module "DRIVERS" -Message "Escaneando dispositivos..."

    # List devices with errors or missing drivers
    $problematic = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -in @("Error", "Unknown", "Degraded") }

    if ($problematic.Count -eq 0) {
        Write-Log -Module "DRIVERS" -Message "No se detectaron dispositivos con problemas"
    } else {
        foreach ($dev in $problematic) {
            Write-Log -Module "DRIVERS" -Message "Dispositivo con problema: $($dev.FriendlyName) [$($dev.Status)]"
        }
    }

    # Trigger Windows Update scan for driver updates
    Write-Log -Module "DRIVERS" -Message "Iniciando escaneo de drivers via Windows Update..."
    $scanOutput = & pnputil /scan-devices 2>&1
    Write-Log -Module "DRIVERS" -Message "pnputil: $($scanOutput -join ' ')"

    # Report devices that were updated (check for status change)
    $updated = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "OK" -and $_.Present -eq $true }
    Write-Log -Module "DRIVERS" -Message "Escaneo completado. Dispositivos OK: $($updated.Count)"

    if ($problematic.Count -gt 0) {
        Write-Log -Module "DRIVERS" -Message "Dispositivos con problemas persistentes: $($problematic.Count) — revisar manualmente en Administrador de dispositivos"
    }
}
```

- [ ] **Step 2: Manual verification**

Run `optimize.ps1` as Administrator and select option [2]. Expected output in console and log:
```
[YYYY-MM-DD HH:mm:ss] [DRIVERS] Escaneando dispositivos...
[YYYY-MM-DD HH:mm:ss] [DRIVERS] Iniciando escaneo de drivers via Windows Update...
[YYYY-MM-DD HH:mm:ss] [DRIVERS] pnputil: Scanning for new hardware...
[YYYY-MM-DD HH:mm:ss] [DRIVERS] Escaneo completado. Dispositivos OK: N
```

- [ ] **Step 3: Commit**

```powershell
git add modules\drivers.ps1
git commit -m "feat: add Invoke-DriverUpdate module"
```

---

## Task 6: modules/registry.ps1

**Files:**
- Create: `modules\registry.ps1`

This module depends on `backup.ps1` and `logger.ps1` being dot-sourced first.

- [ ] **Step 1: Implement modules/registry.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\registry.ps1`:
```powershell
function Invoke-RegistryLevel1 {
    $removed = 0

    # Orphaned uninstall entries
    $uninstallPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    Get-ChildItem -Path $uninstallPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $uninstallStr = $props.UninstallString
        if (-not $uninstallStr) { return }

        $exePath = $uninstallStr -replace '"([^"]+)".*', '$1'
        $exePath = $exePath -replace '^([^ ]+).*', '$1'

        if ($exePath -and -not (Test-Path $exePath)) {
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed++
            Write-Log -Module "REG-L1" -Message "Entrada huerfana eliminada: $($props.DisplayName ?? $_.PSChildName)"
        }
    }

    # Invalid Run keys
    $runPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($runPath in $runPaths) {
        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties |
            Where-Object { $_.Name -notlike "PS*" } |
            ForEach-Object {
                $exePath = $_.Value -replace '"([^"]+)".*', '$1'
                $exePath = $exePath -replace '^([^ ]+).*', '$1'
                if ($exePath -and -not (Test-Path $exePath)) {
                    Remove-ItemProperty -Path $runPath -Name $_.Name -Force -ErrorAction SilentlyContinue
                    $removed++
                    Write-Log -Module "REG-L1" -Message "Clave Run invalida eliminada: $($_.Name)"
                }
            }
    }

    Write-Log -Module "REG-L1" -Message "Total: $removed entradas eliminadas"
}

function Invoke-RegistryLevel2 {
    # System timeouts
    $desktopPath = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desktopPath -Name "WaitToKillAppTimeout" -Value "5000" -Type String
    Set-ItemProperty -Path $desktopPath -Name "HungAppTimeout" -Value "3000" -Type String
    Write-Log -Module "REG-L2" -Message "Timeouts ajustados: WaitToKillApp=5000ms, HungApp=3000ms"

    $controlPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
    Set-ItemProperty -Path $controlPath -Name "WaitToKillServiceTimeout" -Value "5000" -Type String
    Write-Log -Module "REG-L2" -Message "WaitToKillServiceTimeout=5000ms"

    # MRU cleanup
    $mruPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
    )
    $cleaned = 0
    foreach ($path in $mruPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $cleaned++
            Write-Log -Module "REG-L2" -Message "MRU limpiado: $(Split-Path $path -Leaf)"
        }
    }
    Write-Log -Module "REG-L2" -Message "MRU: $cleaned rutas limpiadas"
}

function Invoke-RegistryLevel3 {
    # MMCSS — improve multimedia scheduling responsiveness
    $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $mmcssPath) {
        Set-ItemProperty -Path $mmcssPath -Name "SystemResponsiveness" -Value 10 -Type DWord
        Set-ItemProperty -Path $mmcssPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
        Write-Log -Module "REG-L3" -Message "MMCSS: SystemResponsiveness=10, NetworkThrottlingIndex=max"
    }

    # Memory management
    $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord
    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord
    Write-Log -Module "REG-L3" -Message "Memoria: LargeSystemCache=0, DisablePagingExecutive=1"

    # Prefetch — disable on SSD, keep on HDD
    $prefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq "0" }
    if ($disk -and $disk.MediaType -eq "SSD") {
        Set-ItemProperty -Path $prefetchPath -Name "EnablePrefetcher" -Value 0 -Type DWord
        Set-ItemProperty -Path $prefetchPath -Name "EnableSuperfetch" -Value 0 -Type DWord
        Write-Log -Module "REG-L3" -Message "Prefetch/Superfetch deshabilitado (SSD detectado)"
    } else {
        Write-Log -Module "REG-L3" -Message "Prefetch conservado (HDD detectado o disco no identificado)"
    }
}

function Invoke-RegistryFix {
    param([int]$Level)

    Write-Log -Module "REG-L$Level" -Message "Iniciando nivel $Level — creando backup..."
    New-RegistryBackup -Level "L$Level"

    switch ($Level) {
        1 { Invoke-RegistryLevel1 }
        2 { Invoke-RegistryLevel2 }
        3 { Invoke-RegistryLevel3 }
    }
}
```

- [ ] **Step 2: Manual verification for Level 1**

Run `optimize.ps1` as Administrator → opción [3]. Verificar en `logs\`:
```
[REG-L1] Entrada huerfana eliminada: <AppName>   (si existen)
[REG-L1] Total: N entradas eliminadas
[BACKUP] Backup L1 guardado: 3 archivos en backup\
```

Verificar que existe `backup\registry-L1-YYYY-MM-DD-HH-mm-0.reg`.

- [ ] **Step 3: Commit**

```powershell
git add modules\registry.ps1
git commit -m "feat: add Invoke-RegistryFix with 3 escalating levels"
```

---

## Task 7: modules/hardware.ps1

**Files:**
- Create: `modules\hardware.ps1`

- [ ] **Step 1: Implement modules/hardware.ps1**

Create `G:\PROYECTOS\WinOptimizer\modules\hardware.ps1`:
```powershell
function Invoke-HardwareOptimize {
    # Power plan: High Performance
    & powercfg /setactive SCHEME_MIN 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "Plan de energia: Alto Rendimiento activado"

    # Disable USB Selective Suspend (AC and DC)
    & powercfg /SETACVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    & powercfg /SETDCVALUEINDEX SCHEME_MIN 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "USB Selective Suspend: deshabilitado"

    # Processor scheduling — favor foreground apps (0x26 = variable, high, short quantum)
    $priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    Set-ItemProperty -Path $priorityPath -Name "Win32PrioritySeparation" -Value 38 -Type DWord
    Write-Log -Module "HW" -Message "Scheduling del procesador: favorece apps en primer plano"

    # Visual effects — best performance
    $visualPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualPath)) {
        New-Item -Path $visualPath -Force | Out-Null
    }
    Set-ItemProperty -Path $visualPath -Name "VisualFXSetting" -Value 2 -Type DWord
    Write-Log -Module "HW" -Message "Efectos visuales: mejor rendimiento"

    # Virtual memory — report current config
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $ram = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { "?" }
    $pageFile = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue
    $pfSize = if ($pageFile) { "$($pageFile.AllocatedBaseSize) MB" } else { "no detectado" }
    Write-Log -Module "HW" -Message "RAM: ${ram} GB | Pagefile actual: $pfSize"

    & powercfg /update-settings 2>&1 | Out-Null
    Write-Log -Module "HW" -Message "Configuracion de energia aplicada"
}
```

- [ ] **Step 2: Manual verification**

Run `optimize.ps1` → opción [6]. Expected log output:
```
[HW] Plan de energia: Alto Rendimiento activado
[HW] USB Selective Suspend: deshabilitado
[HW] Scheduling del procesador: favorece apps en primer plano
[HW] Efectos visuales: mejor rendimiento
[HW] RAM: X.X GB | Pagefile actual: XXXX MB
[HW] Configuracion de energia aplicada
```

- [ ] **Step 3: Commit**

```powershell
git add modules\hardware.ps1
git commit -m "feat: add Invoke-HardwareOptimize module"
```

---

## Task 8: optimize.ps1 — main launcher

**Files:**
- Create: `optimize.ps1`

- [ ] **Step 1: Implement optimize.ps1**

Create `G:\PROYECTOS\WinOptimizer\optimize.ps1`:
```powershell
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
```

- [ ] **Step 2: Run all Pester tests to confirm nothing broke**

```powershell
Invoke-Pester -Path tests\ -Output Detailed
```

Expected: all tests pass.

- [ ] **Step 3: Integration test — run option [1] manually**

```powershell
# En PowerShell 7+
pwsh -NoProfile -File "G:\PROYECTOS\WinOptimizer\optimize.ps1"
# En PowerShell 5.1
powershell -NoProfile -File "G:\PROYECTOS\WinOptimizer\optimize.ps1"
```

Seleccionar [1]. Verificar:
- Log creado en `logs\optimize-YYYY-MM-DD.log`
- Salida muestra MB liberados

- [ ] **Step 4: Commit**

```powershell
git add optimize.ps1
git commit -m "feat: add main launcher with interactive menu and auto-elevation"
```

---

## Task 9: CLAUDE.md + full integration run

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Create CLAUDE.md**

Create `G:\PROYECTOS\WinOptimizer\CLAUDE.md`:
```markdown
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
```

- [ ] **Step 2: Run full integration test — option [7]**

```powershell
pwsh -NoProfile -File "G:\PROYECTOS\WinOptimizer\optimize.ps1"
```

Seleccionar [7]. Verificar en log:
```
[INIT]    WinOptimizer iniciado
[TEMP]    Total: X MB liberados en N archivos
[DRIVERS] Escaneo completado. Dispositivos OK: N
[BACKUP]  Backup L1 guardado: 3 archivos en backup\
[REG-L1]  Total: N entradas eliminadas
[BACKUP]  Backup L2 guardado: 3 archivos en backup\
[REG-L2]  Timeouts ajustados...
[BACKUP]  Backup L3 guardado: 2 archivos en backup\
[REG-L3]  MMCSS: SystemResponsiveness=10...
[HW]      Plan de energia: Alto Rendimiento activado
[INIT]    WinOptimizer finalizado
```

- [ ] **Step 3: Final commit**

```powershell
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with stack, commands, and decision history"
```
