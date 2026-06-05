[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$statePath = Join-Path $PSScriptRoot ".demo-state.json"
$BackendPort = 8000
$FrontendPort = 8081

function Get-StateValue {
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $property = $State.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Stop-ProcessTree {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $childrenByParent = @{}
  foreach ($processInfo in $processes) {
    $parentId = [int]$processInfo.ParentProcessId
    if (-not $childrenByParent.ContainsKey($parentId)) {
      $childrenByParent[$parentId] = New-Object System.Collections.Generic.List[int]
    }
    [void]$childrenByParent[$parentId].Add([int]$processInfo.ProcessId)
  }

  $ids = New-Object System.Collections.Generic.List[int]
  $queue = New-Object System.Collections.Generic.Queue[int]
  $queue.Enqueue($ProcessId)
  while ($queue.Count -gt 0) {
    $currentId = $queue.Dequeue()
    [void]$ids.Add($currentId)
    if ($childrenByParent.ContainsKey($currentId)) {
      foreach ($childId in $childrenByParent[$currentId]) {
        $queue.Enqueue($childId)
      }
    }
  }

  $idsArray = $ids.ToArray()
  [array]::Reverse($idsArray)
  foreach ($id in $idsArray) {
    try {
      Stop-Process -Id $id -Force -ErrorAction Stop
    }
    catch {
      # El proceso pudo haber terminado entre la deteccion y el cierre.
    }
  }
}

function Stop-DemoOrphans {
  $patterns = @(
    "flutter\.bat.*run -d web-server.*--web-port $FrontendPort",
    "flutter\.bat.*run -d (chrome|edge).*--web-port $FrontendPort",
    "flutter_tools\.snapshot.*run -d web-server.*--web-port $FrontendPort",
    "flutter_tools\.snapshot.*run -d (chrome|edge).*--web-port $FrontendPort",
    "http\.server $FrontendPort",
    "uvicorn app\.main:aplicacion --reload --port $BackendPort",
    "(chrome|msedge)\.exe.*localhost:$FrontendPort"
  )

  $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  foreach ($processInfo in $processes) {
    $commandLine = [string]$processInfo.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
      continue
    }

    foreach ($pattern in $patterns) {
      if ($commandLine -match $pattern) {
        Stop-ProcessTree -ProcessId ([int]$processInfo.ProcessId)
        break
      }
    }
  }
}

if (-not (Test-Path $statePath)) {
  Write-Host "No hay una sesion demo registrada para detener." -ForegroundColor DarkYellow
  Stop-DemoOrphans
  exit 0
}

$state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
$allTerminalIds = @(
  (Get-StateValue -State $state -Name "backend_terminal_id"),
  (Get-StateValue -State $state -Name "central_terminal_id"),
  (Get-StateValue -State $state -Name "driver_terminal_id"),
  (Get-StateValue -State $state -Name "frontend_terminal_id"),
  (Get-StateValue -State $state -Name "central_browser_id"),
  (Get-StateValue -State $state -Name "driver_browser_id")
)

$terminalIds = New-Object System.Collections.Generic.List[int]
foreach ($idCandidate in $allTerminalIds) {
  if ($null -ne $idCandidate -and [string]::IsNullOrWhiteSpace([string]$idCandidate) -eq $false) {
    [void]$terminalIds.Add([int]$idCandidate)
  }
}

if ($terminalIds.Count -eq 0) {
  Write-Host "No se encontraron IDs de terminal en el estado guardado." -ForegroundColor DarkYellow
  Stop-DemoOrphans
  Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
  exit 0
}

foreach ($terminalId in $terminalIds) {
  try {
    Stop-ProcessTree -ProcessId ([int]$terminalId)
    Write-Host ("Terminal detenida (ID {0})" -f $terminalId) -ForegroundColor Green
  }
  catch {
    Write-Host ("No se pudo detener ID {0} (posiblemente ya estaba cerrado)." -f $terminalId) -ForegroundColor DarkYellow
  }
}

Stop-DemoOrphans
Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
Write-Host "Sesion demo detenida y estado limpiado." -ForegroundColor Cyan
