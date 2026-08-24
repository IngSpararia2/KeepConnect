[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$generateScript = Join-Path $PSScriptRoot 'generar_apk.ps1'

if (-not (Test-Path -LiteralPath $generateScript)) {
    throw "No se encontró el script base: $generateScript"
}

Write-Host 'Actualizando la APK con las dependencias y el SDK verificados...' -ForegroundColor Yellow

$parameters = @{ ReutilizarCache = $true }

& $generateScript @parameters
exit $LASTEXITCODE
