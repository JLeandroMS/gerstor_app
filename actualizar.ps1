param([string]$Device = '')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter no esta en PATH.' }
Write-Host 'Detene cualquier flutter run anterior. Conecta el telefono y acepta la depuracion USB.'
# Fuerza reconstruccion nativa: ni hot reload ni hot restart actualizan Kotlin.
& flutter clean
if ($LASTEXITCODE -ne 0) { throw 'Fallo flutter clean.' }
& (Join-Path $PSScriptRoot 'preparar.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Fallo la preparacion; no se iniciara una version incompleta.' }
if ($Device) { & flutter run -d $Device } else { & flutter run }
if ($LASTEXITCODE -ne 0) { throw 'La compilacion o ejecucion fallo. Copia el primer error de la terminal.' }
