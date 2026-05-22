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
    if ($null -eq $keys) {
        throw "[FALLO] Nivel de backup invalido | Niveles validos: L1, L2, L3 | Recibido: $Level"
    }
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
