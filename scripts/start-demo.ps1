[CmdletBinding()]
param(
  [string]$ApiBaseUrl = "http://localhost:8000",
  [string]$BackendHealthUrl = "http://localhost:8000/health",
  [int]$BackendPort = 8000,
  [string]$CentralDevice = "chrome",
  [string]$DriverDevice = "edge",
  [switch]$ForceRestart,
  [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendPath = Join-Path $repoRoot "backend"
$mobilePath = Join-Path $repoRoot "mobile_app"
$requirementsPath = Join-Path $backendPath "requirements.txt"
$statePath = Join-Path $PSScriptRoot ".demo-state.json"

$PythonExecutable = ""
$UsePyLauncher = $false
$FlutterExecutable = ""

function Write-Step {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host ""
  Write-Host ("==> {0}" -f $Message) -ForegroundColor Cyan
}

function Resolve-Executable {
  param([Parameter(Mandatory = $true)][string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $command) {
    return $null
  }
  return $command.Source
}

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Write-Host (" - {0}" -f $Description)
  Push-Location $WorkingDirectory
  try {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
      $argumentsText = $Arguments -join ' '
      $errorMessage = 'El comando fallo con codigo {0}. Comando {1} {2}' -f $LASTEXITCODE, $Executable, $argumentsText
      throw $errorMessage
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-PythonCommand {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $allArguments = if ($UsePyLauncher) { @("-3") + $Arguments } else { $Arguments }
  Invoke-CheckedCommand -Executable $PythonExecutable -Arguments $allArguments -WorkingDirectory $WorkingDirectory -Description $Description
}

function Invoke-FlutterCommand {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Invoke-CheckedCommand -Executable $FlutterExecutable -Arguments $Arguments -WorkingDirectory $WorkingDirectory -Description $Description
}

function Get-PlatformForDevice {
  param([Parameter(Mandatory = $true)][string]$Device)

  $normalized = $Device.ToLowerInvariant()
  if ($normalized -in @("chrome", "edge", "web-server")) {
    return "web"
  }
  if ($normalized -eq "windows") {
    return "windows"
  }
  if ($normalized -eq "android" -or $normalized.StartsWith("emulator-")) {
    return "android"
  }
  if ($normalized -eq "ios") {
    return "ios"
  }
  if ($normalized -eq "linux") {
    return "linux"
  }
  if ($normalized -eq "macos") {
    return "macos"
  }
  return $null
}

function Get-FlutterDeviceIds {
  $rawOutput = & $FlutterExecutable devices --machine
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo consultar la lista de dispositivos Flutter."
  }

  if ([string]::IsNullOrWhiteSpace($rawOutput)) {
    return @()
  }

  $devices = $rawOutput | ConvertFrom-Json
  if ($null -eq $devices) {
    return @()
  }

  return @($devices | ForEach-Object { $_.id.ToString() })
}

function Stop-ExistingSession {
  param([Parameter(Mandatory = $true)][string]$SessionStatePath)

  if (-not (Test-Path $SessionStatePath)) {
    return
  }

  $state = Get-Content -Path $SessionStatePath -Raw | ConvertFrom-Json
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

  foreach ($terminalId in $terminalIds) {
    try {
      Stop-Process -Id ([int]$terminalId) -Force -ErrorAction Stop
      Write-Host (" - Terminal detenido (ID {0})" -f $terminalId)
    }
    catch {
      Write-Host (" - ID {0} no estaba activo" -f $terminalId) -ForegroundColor DarkYellow
    }
  }

  Remove-Item -Path $SessionStatePath -Force -ErrorAction SilentlyContinue
}

function Start-TerminalWindow {
  param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$CommandText
  )

  $safeTitle = $Title.Replace("'", "''")
  $safeDirectory = $WorkingDirectory.Replace("'", "''")
  $bootstrap = @(
    "`$Host.UI.RawUI.WindowTitle = '$safeTitle'",
    "Set-Location '$safeDirectory'",
    "Write-Host '[$safeTitle] Iniciado' -ForegroundColor Green",
    $CommandText
  ) -join "; "

  return Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    $bootstrap
  ) -PassThru
}

function Wait-BackendReady {
  param(
    [Parameter(Mandatory = $true)][string]$HealthUrl,
    [int]$TimeoutSeconds = 45
  )

  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    try {
      $response = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 3
      if ($null -ne $response -and $response.status -eq "ok") {
        return $true
      }
    }
    catch {
      # Backend todavia no listo.
    }
    Start-Sleep -Seconds 1
  }

  return $false
}

if (-not (Test-Path $backendPath)) {
  throw "No se encontro la carpeta backend en: $backendPath"
}
if (-not (Test-Path $mobilePath)) {
  throw "No se encontro la carpeta mobile_app en: $mobilePath"
}
if (-not (Test-Path $requirementsPath)) {
  throw "No se encontro requirements.txt en: $requirementsPath"
}

Write-Step "Verificando herramientas base"
$PythonExecutable = Resolve-Executable "python"
if (-not $PythonExecutable) {
  $PythonExecutable = Resolve-Executable "py"
  if ($PythonExecutable) {
    $UsePyLauncher = $true
  }
}
if (-not $PythonExecutable) {
  throw "Python no esta instalado o no esta en PATH."
}

$FlutterExecutable = Resolve-Executable "flutter"
if (-not $FlutterExecutable) {
  throw "Flutter no esta instalado o no esta en PATH."
}

$pythonLabel = if ($UsePyLauncher) { "$PythonExecutable -3" } else { $PythonExecutable }
Write-Host (" - Python detectado: {0}" -f $pythonLabel)
Write-Host (" - Flutter detectado: {0}" -f $FlutterExecutable)

Write-Step "Instalando/verificando dependencias backend"
Invoke-PythonCommand -Arguments @("-m", "pip", "install", "-r", $requirementsPath) -WorkingDirectory $backendPath -Description "pip install -r backend/requirements.txt"

Write-Step "Verificando plataformas Flutter requeridas"
$requiredPlatforms = New-Object System.Collections.Generic.HashSet[string]
foreach ($device in @($CentralDevice, $DriverDevice)) {
  $platform = Get-PlatformForDevice -Device $device
  if ($null -ne $platform) {
    [void]$requiredPlatforms.Add($platform)
  }
}

$missingPlatforms = New-Object System.Collections.Generic.List[string]
foreach ($platformName in $requiredPlatforms) {
  $platformPath = Join-Path $mobilePath $platformName
  if (-not (Test-Path $platformPath)) {
    [void]$missingPlatforms.Add($platformName)
  }
}

if ($missingPlatforms.Count -gt 0) {
  $platformsArg = "--platforms=$($missingPlatforms.ToArray() -join ',')"
  Invoke-FlutterCommand -Arguments @("create", $platformsArg, ".") -WorkingDirectory $mobilePath -Description "flutter create para plataformas faltantes"
}
else {
  Write-Host " - Las plataformas necesarias ya existen."
}

Write-Step "Instalando/verificando dependencias Flutter"
Invoke-FlutterCommand -Arguments @("pub", "get") -WorkingDirectory $mobilePath -Description "flutter pub get"

Write-Step "Verificando dispositivos Flutter"
$availableDevices = Get-FlutterDeviceIds
if ($availableDevices.Count -eq 0) {
  throw "Flutter no detecto dispositivos. Ejecuta 'flutter devices' para diagnostico."
}

if (-not ($availableDevices -contains $CentralDevice)) {
  throw "No se encontro el dispositivo '$CentralDevice'. Disponibles: $($availableDevices -join ', ')"
}
if (-not ($availableDevices -contains $DriverDevice)) {
  throw "No se encontro el dispositivo '$DriverDevice'. Disponibles: $($availableDevices -join ', ')"
}
Write-Host (" - Dispositivos disponibles: {0}" -f ($availableDevices -join ", "))

if (Test-Path $statePath) {
  if ($ForceRestart) {
    Write-Step "Deteniendo sesion anterior"
    Stop-ExistingSession -SessionStatePath $statePath
  }
  else {
    throw "Ya existe una sesion activa. Ejecuta scripts/stop-demo.ps1 o relanza con -ForceRestart."
  }
}

if ($NoLaunch) {
  Write-Step "Verificacion completa"
  Write-Host "Todo listo. No se lanzaron terminales porque se uso -NoLaunch." -ForegroundColor Green
  exit 0
}

$pythonRunPrefix = if ($UsePyLauncher) { "py -3" } else { '"{0}"' -f $PythonExecutable }
$backendCommand = '{0} -m uvicorn app.main:aplicacion --reload --port {1}' -f $pythonRunPrefix, $BackendPort
$centralCommand = 'flutter run -d {0} --dart-define=API_BASE_URL="{1}"' -f $CentralDevice, $ApiBaseUrl
$driverCommand = 'flutter run -d {0} --dart-define=API_BASE_URL="{1}"' -f $DriverDevice, $ApiBaseUrl

Write-Step "Lanzando backend"
$backendTerminal = Start-TerminalWindow -Title "PAE Backend" -WorkingDirectory $backendPath -CommandText $backendCommand

Write-Host " - Esperando backend listo..."
if (-not (Wait-BackendReady -HealthUrl $BackendHealthUrl -TimeoutSeconds 45)) {
  try {
    Stop-Process -Id $backendTerminal.Id -Force -ErrorAction SilentlyContinue
  }
  catch {
    # Ignorar error al cerrar proceso fallido.
  }
  throw "El backend no respondio en $BackendHealthUrl dentro del tiempo esperado."
}

Write-Step "Lanzando app Central"
$centralTerminal = Start-TerminalWindow -Title "PAE Central" -WorkingDirectory $mobilePath -CommandText $centralCommand

Write-Step "Lanzando app Repartidor"
$driverTerminal = Start-TerminalWindow -Title "PAE Repartidor" -WorkingDirectory $mobilePath -CommandText $driverCommand

$state = [ordered]@{
  started_at = (Get-Date).ToString("s")
  api_base_url = $ApiBaseUrl
  backend_health_url = $BackendHealthUrl
  central_device = $CentralDevice
  driver_device = $DriverDevice
  backend_terminal_id = $backendTerminal.Id
  central_terminal_id = $centralTerminal.Id
  driver_terminal_id = $driverTerminal.Id
}
$state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8

Write-Step "Sesion demo iniciada"
Write-Host (" - Backend terminal PID: {0}" -f $backendTerminal.Id)
Write-Host (" - Central terminal PID: {0}" -f $centralTerminal.Id)
Write-Host (" - Repartidor terminal PID: {0}" -f $driverTerminal.Id)
Write-Host ""
Write-Host "Para detener todo rapido:" -ForegroundColor Yellow
Write-Host ("powershell -ExecutionPolicy Bypass -File `"{0}`"" -f (Join-Path $PSScriptRoot "stop-demo.ps1")) -ForegroundColor Yellow
