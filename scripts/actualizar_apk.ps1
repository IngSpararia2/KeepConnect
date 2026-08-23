[CmdletBinding()]
param(
    # Omite las pruebas automatizadas, por ejemplo cuando solo necesitas una APK urgente.
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$generateScript = Join-Path $PSScriptRoot 'generar_apk.ps1'

if (-not (Test-Path -LiteralPath $generateScript)) {
    throw "No se encontró el script base: $generateScript"
}

Write-Host 'Actualizando la APK con las dependencias y el SDK verificados...' -ForegroundColor Yellow

$parameters = @{ ReutilizarCache = $true }
if ($SkipTests) {
    $parameters.SkipTests = $true
}

& $generateScript @parameters
exit $LASTEXITCODE
