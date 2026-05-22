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
