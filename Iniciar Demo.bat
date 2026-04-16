@echo off
setlocal
TITLE Lanzador Grafico Demo PAE

set "ROOT=%~dp0"
set "APP_DIR=%ROOT%mobile_app"
set "EXE=%APP_DIR%\build\windows\x64\runner\Release\pae_mobile.exe"
set "TARGET_MARKER=%APP_DIR%\build\windows\x64\runner\Release\.demo_launcher_target"
set "NEEDS_BUILD=0"

if not exist "%EXE%" set "NEEDS_BUILD=1"
if not exist "%TARGET_MARKER%" set "NEEDS_BUILD=1"
if exist "%TARGET_MARKER%" (
  findstr /x /c:"demo_launcher_main" "%TARGET_MARKER%" >nul
  if errorlevel 1 set "NEEDS_BUILD=1"
)

if "%NEEDS_BUILD%"=="1" (
	echo =======================================================
	echo Preparando lanzador Flutter de la demo...
	echo =======================================================
	pushd "%APP_DIR%"
	call flutter pub get
	if errorlevel 1 goto :build_error
	call flutter build windows --release -t lib\demo_launcher_main.dart
	if errorlevel 1 goto :build_error
	echo demo_launcher_main>"%TARGET_MARKER%"
	popd
)

start "" "%EXE%"
exit /b 0

:build_error
popd
echo.
echo Error al compilar el lanzador Flutter.
pause
exit /b 1
