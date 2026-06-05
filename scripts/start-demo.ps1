[CmdletBinding()]
param(
  [string]$ApiBaseUrl = "http://localhost:8000",
  [string]$BackendHealthUrl = "http://localhost:8000/health",
  [int]$BackendPort = 8000,
  [int]$FrontendPort = 8081,
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

function Test-WebBrowserDevice {
  param([Parameter(Mandatory = $true)][string]$Device)

  return $Device.ToLowerInvariant() -in @("chrome", "edge")
}

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

function Get-Neo4jEndpoint {
  $uriText = if ([string]::IsNullOrWhiteSpace($env:NEO4J_URI)) {
    "bolt://127.0.0.1:7687"
  }
  else {
    $env:NEO4J_URI
  }

  try {
    $uri = [System.Uri]$uriText
    $hostName = if ([string]::IsNullOrWhiteSpace($uri.Host)) { "127.0.0.1" } else { $uri.Host }
    $port = if ($uri.Port -gt 0) { $uri.Port } else { 7687 }
  }
  catch {
    $hostName = "127.0.0.1"
    $port = 7687
  }

  return [pscustomobject]@{
    Uri = $uriText
    Host = $hostName
    Port = $port
    Database = if ([string]::IsNullOrWhiteSpace($env:NEO4J_DATABASE)) { "proyectopae" } else { $env:NEO4J_DATABASE }
  }
}

function Test-TcpPort {
  param(
    [Parameter(Mandatory = $true)][string]$HostName,
    [Parameter(Mandatory = $true)][int]$Port,
    [int]$TimeoutMilliseconds = 1500
  )

  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
      return $false
    }
    $client.EndConnect($asyncResult)
    return $true
  }
  catch {
    return $false
  }
  finally {
    $client.Close()
  }
}

function Test-Neo4jPreflight {
  $endpoint = Get-Neo4jEndpoint
  Write-Step "Verificando Neo4j"

  if (Test-TcpPort -HostName $endpoint.Host -Port $endpoint.Port) {
    Write-Host (" - Neo4j detectado en {0}:{1}" -f $endpoint.Host, $endpoint.Port)
    return
  }

  Write-Host ""
  Write-Host "NEO4J NO ESTA INICIADO" -ForegroundColor Red
  Write-Host ""
  Write-Host ("No se pudo conectar con Neo4j en {0}:{1}." -f $endpoint.Host, $endpoint.Port)
  Write-Host ("Configuracion esperada: NEO4J_URI={0}, NEO4J_DATABASE={1}" -f $endpoint.Uri, $endpoint.Database)
  Write-Host ""
  Write-Host "Que hacer:"
  Write-Host "1. Abre Neo4j Desktop."
  Write-Host ("2. Inicia la base/proyecto '{0}'." -f $endpoint.Database)
  Write-Host "3. Espera a que el estado sea Started/Running."
  Write-Host "4. Vuelve a pulsar Iniciar Demo en el lanzador."
  Write-Host ""
  Write-Host "No se ha iniciado backend, Flutter ni navegadores."
  exit 20
}

function Resolve-BrowserExecutable {
  param([Parameter(Mandatory = $true)][string]$Device)

  $normalized = $Device.ToLowerInvariant()
  if ($normalized -eq "chrome") {
    $chrome = Resolve-Executable "chrome"
    if ($chrome) {
      return $chrome
    }
    $defaultChrome = Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"
    if (Test-Path $defaultChrome) {
      return $defaultChrome
    }
  }

  if ($normalized -eq "edge") {
    $edge = Resolve-Executable "msedge"
    if ($edge) {
      return $edge
    }
    $defaultEdge = Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"
    if (Test-Path $defaultEdge) {
      return $defaultEdge
    }
  }

  throw "No se encontro ejecutable para el navegador '$Device'."
}

function Stop-ExistingSession {
  param([Parameter(Mandatory = $true)][string]$SessionStatePath)

  if (-not (Test-Path $SessionStatePath)) {
    return
  }

  $state = Get-Content -Path $SessionStatePath -Raw | ConvertFrom-Json
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

  foreach ($terminalId in $terminalIds) {
    try {
      Stop-ProcessTree -ProcessId ([int]$terminalId)
      Write-Host (" - Terminal detenido (ID {0})" -f $terminalId)
    }
    catch {
      Write-Host (" - ID {0} no estaba activo" -f $terminalId) -ForegroundColor DarkYellow
    }
  }

  Remove-Item -Path $SessionStatePath -Force -ErrorAction SilentlyContinue
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

function Wait-HttpReady {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$TimeoutSeconds = 60
  )

  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    try {
      $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 3 -UseBasicParsing
      if ($null -ne $response -and [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500) {
        return $true
      }
    }
    catch {
      # Servidor todavia no listo.
    }
    Start-Sleep -Seconds 1
  }

  return $false
}

function Stop-StartedProcesses {
  param([Parameter(Mandatory = $true)]$ProcessIds)

  foreach ($processId in @($ProcessIds)) {
    if ($null -eq $processId) {
      continue
    }
    try {
      Stop-ProcessTree -ProcessId ([int]$processId)
    }
    catch {
      # El proceso pudo haber terminado durante el arranque fallido.
    }
  }
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

Test-Neo4jPreflight

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

# Intentar detectar venv local
$venvPath = Join-Path $backendPath ".venv"
$venvPython = Join-Path $venvPath "Scripts\python.exe"
if (Test-Path $venvPython) {
  $PythonExecutable = $venvPython
  $pythonLabel = "Python (Virtual Env)"
  $UsePyLauncher = $false
}

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

if ($ForceRestart) {
  Write-Step "Limpiando procesos demo huerfanos"
  Stop-DemoOrphans
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
$useSharedWebServer = (Test-WebBrowserDevice -Device $CentralDevice) -and (Test-WebBrowserDevice -Device $DriverDevice)
$startedProcessIds = New-Object System.Collections.Generic.List[int]
$frontendUrl = $null
$frontendLaunchUrl = $null
$webBuildPath = $null
$state = $null

try {
  if ($useSharedWebServer) {
    $frontendUrl = "http://localhost:$FrontendPort"
    $frontendLaunchUrl = "{0}/?demo={1}" -f $frontendUrl.TrimEnd("/"), ([DateTimeOffset]::Now.ToUnixTimeSeconds())
    $webBuildPath = Join-Path $mobilePath "build\web"

    Write-Step "Compilando app Flutter Web"
    Invoke-FlutterCommand -Arguments @("build", "web", "--dart-define=API_BASE_URL=$ApiBaseUrl") -WorkingDirectory $mobilePath -Description "flutter build web"

    if (-not (Test-Path (Join-Path $webBuildPath "index.html"))) {
      throw "No se encontro index.html en la build web: $webBuildPath"
    }
  }

  Write-Step "Lanzando backend"
  $backendTerminal = Start-TerminalWindow -Title "PAE Backend" -WorkingDirectory $backendPath -CommandText $backendCommand
  [void]$startedProcessIds.Add([int]$backendTerminal.Id)

  Write-Host " - Esperando backend listo..."
  if (-not (Wait-BackendReady -HealthUrl $BackendHealthUrl -TimeoutSeconds 45)) {
    throw "El backend no respondio en $BackendHealthUrl dentro del tiempo esperado."
  }

  if ($useSharedWebServer) {
    $frontendCommand = '{0} -m http.server {1} --bind localhost' -f $pythonRunPrefix, $FrontendPort

    Write-Step "Lanzando servidor web Flutter"
    $frontendTerminal = Start-TerminalWindow -Title "PAE Flutter Web" -WorkingDirectory $webBuildPath -CommandText $frontendCommand
    [void]$startedProcessIds.Add([int]$frontendTerminal.Id)

    Write-Host " - Esperando frontend listo..."
    if (-not (Wait-HttpReady -Url $frontendUrl -TimeoutSeconds 90)) {
      throw "El frontend no respondio en $frontendUrl dentro del tiempo esperado."
    }

    Write-Step "Abriendo app Central"
    $centralBrowser = Start-Process -FilePath (Resolve-BrowserExecutable -Device $CentralDevice) -ArgumentList @("--new-window", $frontendLaunchUrl) -PassThru
    [void]$startedProcessIds.Add([int]$centralBrowser.Id)

    Write-Step "Abriendo app Repartidor"
    $driverBrowser = Start-Process -FilePath (Resolve-BrowserExecutable -Device $DriverDevice) -ArgumentList @("--new-window", $frontendLaunchUrl) -PassThru
    [void]$startedProcessIds.Add([int]$driverBrowser.Id)

    $state = [ordered]@{
      started_at = (Get-Date).ToString("s")
      api_base_url = $ApiBaseUrl
      backend_health_url = $BackendHealthUrl
      frontend_url = $frontendUrl
      frontend_launch_url = $frontendLaunchUrl
      central_device = $CentralDevice
      driver_device = $DriverDevice
      backend_terminal_id = $backendTerminal.Id
      frontend_terminal_id = $frontendTerminal.Id
      central_browser_id = $centralBrowser.Id
      driver_browser_id = $driverBrowser.Id
    }
  }
  else {
    Write-Step "Lanzando app Central"
    $centralTerminal = Start-TerminalWindow -Title "PAE Central" -WorkingDirectory $mobilePath -CommandText $centralCommand
    [void]$startedProcessIds.Add([int]$centralTerminal.Id)

    Write-Step "Lanzando app Repartidor"
    $driverTerminal = Start-TerminalWindow -Title "PAE Repartidor" -WorkingDirectory $mobilePath -CommandText $driverCommand
    [void]$startedProcessIds.Add([int]$driverTerminal.Id)

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
  }

  $state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
}
catch {
  Write-Host " - Error durante el arranque. Limpiando procesos iniciados..." -ForegroundColor DarkYellow
  Stop-StartedProcesses -ProcessIds $startedProcessIds
  Stop-DemoOrphans
  Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
  throw
}

Write-Step "Sesion demo iniciada"
Write-Host (" - Backend terminal PID: {0}" -f $backendTerminal.Id)
if ($useSharedWebServer) {
  Write-Host (" - Frontend web terminal PID: {0}" -f $frontendTerminal.Id)
  Write-Host (" - Central navegador PID: {0}" -f $centralBrowser.Id)
  Write-Host (" - Repartidor navegador PID: {0}" -f $driverBrowser.Id)
}
else {
  Write-Host (" - Central terminal PID: {0}" -f $centralTerminal.Id)
  Write-Host (" - Repartidor terminal PID: {0}" -f $driverTerminal.Id)
}
Write-Host ""
Write-Host "Para detener todo rapido:" -ForegroundColor Yellow
Write-Host ("powershell -ExecutionPolicy Bypass -File `"{0}`"" -f (Join-Path $PSScriptRoot "stop-demo.ps1")) -ForegroundColor Yellow
