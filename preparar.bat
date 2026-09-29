@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0preparar.ps1"
if errorlevel 1 (
  echo No se pudo preparar el proyecto. Lee el error anterior.
  pause
  exit /b 1
)
pause
