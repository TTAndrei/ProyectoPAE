@echo off
TITLE Detener Demo PAE
powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0scripts\stop-demo.ps1"
exit /b 0
