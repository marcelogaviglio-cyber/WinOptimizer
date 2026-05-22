function Write-Log {
    param(
        [string]$Module,
        [string]$Message
    )
    if (-not $global:WO_LogFile) { throw "[FALLO] WO_LogFile no inicializado | logger.ps1 | Inicializar global:WO_LogFile en optimize.ps1 antes de llamar Write-Log" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Module] $Message"
    Write-Host $line
    $logDir = Split-Path $global:WO_LogFile -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    try {
        Add-Content -Path $global:WO_LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Write-Log: no se pudo escribir al archivo de log: $_"
    }
}
