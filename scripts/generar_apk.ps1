[CmdletBinding()]
param(
    # Mantiene los artefactos de Gradle para una compilación posterior más rápida.
    [switch]$ReutilizarCache
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$GradleWrapper = Join-Path $ProjectRoot 'android\gradlew.bat'
$UseSafeBuildPath = $ProjectRoot -match '\s'
# Flutter conserva rutas absolutas de los assets nativos. Una unidad temporal
# estable evita espacios en la ruta durante toda la compilación.
$SafeBuildDrive = 'K:'
$SafeBuildPath = "$SafeBuildDrive\"
$RunRoot = $ProjectRoot
$safeDriveCreated = $false
$locationChanged = $false
$scriptFailed = $false
$failureMessage = $null
$FlutterExecutable = 'flutter'

function Invoke-Flutter {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Write-Host ("> flutter " + ($Arguments -join ' ')) -ForegroundColor Cyan
    & $FlutterExecutable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter terminó con código $LASTEXITCODE."
    }
}

try {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'No se encontró Flutter en PATH. Instálalo o reinicia la terminal después de configurarlo.'
    }

    if (-not (Test-Path -LiteralPath $GradleWrapper)) {
        throw "No se encontró el wrapper de Gradle esperado: $GradleWrapper"
    }

    Push-Location $RunRoot
    $locationChanged = $true

    # Flutter 3.44 puede fallar al invocar assets nativos desde rutas con
    # espacios. Tests y APK se ejecutan desde una unidad temporal sin espacios.
    if ($UseSafeBuildPath) {
        if (Test-Path -LiteralPath $SafeBuildPath) {
            throw "La unidad temporal $SafeBuildDrive está en uso. Libérala o cambia SafeBuildDrive en generar_apk.ps1."
        }

        # El caché puede apuntar a una unidad temporal eliminada tras una
        # ejecución anterior; Flutter lo regenerará con la unidad actual.
        $nativeAssetsCache = Join-Path $ProjectRoot '.dart_tool\hooks_runner'
        if (Test-Path -LiteralPath $nativeAssetsCache) {
            Remove-Item -LiteralPath $nativeAssetsCache -Recurse -Force
        }

        $substOutput = & subst.exe $SafeBuildDrive $ProjectRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo crear la unidad temporal para compilar: $($substOutput -join ' ')"
        }
        $safeDriveCreated = $true
        $RunRoot = $SafeBuildPath
        $FlutterExecutable = Join-Path $RunRoot '.tooling\flutter\bin\flutter.bat'
        if (-not (Test-Path -LiteralPath $FlutterExecutable)) {
            throw "No se encontró Flutter en la ruta temporal: $FlutterExecutable"
        }

        Pop-Location
        $locationChanged = $false
        Push-Location $RunRoot
        $locationChanged = $true
    }

    if (-not $ReutilizarCache) {
        Write-Host 'Limpiando la compilación anterior...' -ForegroundColor Yellow
        Invoke-Flutter -Arguments @('clean')
    }

    if ($UseSafeBuildPath) {
        Write-Host 'Sincronizando dependencias para la compilación...' -ForegroundColor Yellow
        Invoke-Flutter -Arguments @('pub', 'get')
    }

    Write-Host 'Generando APK de depuración...' -ForegroundColor Yellow
    Invoke-Flutter -Arguments @('build', 'apk', '--debug', '--no-pub')

    $apkPath = Join-Path $RunRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "Flutter finalizó sin crear la APK esperada: $apkPath"
    }

    Write-Host "APK lista: $(Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-debug.apk')" -ForegroundColor Green
}
catch {
    $scriptFailed = $true
    $failureMessage = $_.Exception.Message
}
finally {
    if ($locationChanged) {
        Pop-Location
    }

    if ($safeDriveCreated) {
        & subst.exe $SafeBuildDrive /D
        # Restaura la configuración para ejecutar Flutter normalmente desde VS Code.
        Push-Location $ProjectRoot
        try {
            & flutter pub get | Out-Host
        }
        catch {
            Write-Warning 'No se pudo restaurar pub get en la ruta normal del proyecto.'
        }
        Pop-Location
    }
}

if ($scriptFailed) {
    Write-Error $failureMessage
    exit 1
}
