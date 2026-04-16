[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$statePath = Join-Path $PSScriptRoot ".demo-state.json"

if (-not (Test-Path $statePath)) {
  Write-Host "No hay una sesion demo registrada para detener." -ForegroundColor DarkYellow
  exit 0
}

$state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
$allTerminalIds = @(
  $state.backend_terminal_id,
  $state.central_terminal_id,
  $state.driver_terminal_id
)

$terminalIds = New-Object System.Collections.Generic.List[int]
foreach ($idCandidate in $allTerminalIds) {
  if ($null -ne $idCandidate -and [string]::IsNullOrWhiteSpace([string]$idCandidate) -eq $false) {
    [void]$terminalIds.Add([int]$idCandidate)
  }
}

if ($terminalIds.Count -eq 0) {
  Write-Host "No se encontraron IDs de terminal en el estado guardado." -ForegroundColor DarkYellow
  Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
  exit 0
}

foreach ($terminalId in $terminalIds) {
  try {
    Stop-Process -Id ([int]$terminalId) -Force -ErrorAction Stop
    Write-Host ("Terminal detenida (ID {0})" -f $terminalId) -ForegroundColor Green
  }
  catch {
    Write-Host ("No se pudo detener ID {0} (posiblemente ya estaba cerrado)." -f $terminalId) -ForegroundColor DarkYellow
  }
}

Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
Write-Host "Sesion demo detenida y estado limpiado." -ForegroundColor Cyan
