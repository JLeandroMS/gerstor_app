@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0actualizar.ps1" %*
if errorlevel 1 (
  echo La actualizacion fallo. Revisa el primer error mostrado.
  pause
  exit /b 1
)
pause
