[CmdletBinding()]
param(
    # Mantiene los artefactos de Gradle para una compilación posterior más rápida.
    [switch]$ReutilizarCache
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$UseSafeBuildPath = $ProjectRoot -match '\s'
# Flutter conserva rutas absolutas de los assets nativos. Una unidad temporal
# estable evita espacios en la ruta durante toda la validación y compilación.
$SafeBuildDrive = 'K:'
$SafeBuildPath = "$SafeBuildDrive\"
$RunRoot = $ProjectRoot
$safeDriveCreated = $false
$locationChanged = $false
$primaryFailure = $null
$cleanupFailures = [System.Collections.Generic.List[string]]::new()
$FlutterExecutable = $null
$GlobalFlutterExecutable = $null

function Invoke-Flutter {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    Write-Host ("> flutter " + ($Arguments -join ' ')) -ForegroundColor Cyan
    & $FlutterExecutable @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "La etapa '$Stage' falló (código $exitCode)."
    }
}

try {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCommand) {
        throw 'No se encontró Flutter en PATH. Instálalo o reinicia la terminal después de configurarlo.'
    }
    $GlobalFlutterExecutable = $flutterCommand.Source
    $FlutterExecutable = $GlobalFlutterExecutable

    # Flutter crea o repara su wrapper Android antes de ejecutar Gradle. Por eso
    # no se exige un gradlew generado/ignorado como precondición del checkout.
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
        $substExitCode = $LASTEXITCODE
        if ($substExitCode -ne 0) {
            throw "No se pudo crear la unidad temporal para compilar: $($substOutput -join ' ')"
        }
        $safeDriveCreated = $true
        $RunRoot = $SafeBuildPath
        $FlutterExecutable = Join-Path $RunRoot '.tooling\flutter\bin\flutter.bat'
        if (-not (Test-Path -LiteralPath $FlutterExecutable)) {
            throw "No se encontró Flutter local en $FlutterExecutable. Ejecuta primero la preparación del SDK local del proyecto."
        }
    }

    Push-Location $RunRoot
    $locationChanged = $true

    if (-not $ReutilizarCache) {
        Write-Host 'Limpiando la compilación anterior...' -ForegroundColor Yellow
        Invoke-Flutter -Stage 'flutter clean' -Arguments @('clean')
    }

    Write-Host 'Sincronizando dependencias...' -ForegroundColor Yellow
    Invoke-Flutter -Stage 'flutter pub get' -Arguments @('pub', 'get')

    # El analysis server de Flutter 3.44 genera JSON inválido cuando la raíz es
    # una unidad SUBST. Analizar desde la ruta real no requiere assets nativos;
    # tests y build vuelven a la ruta segura inmediatamente después.
    if ($UseSafeBuildPath) {
        Pop-Location
        $locationChanged = $false
        $FlutterExecutable = $GlobalFlutterExecutable
        Push-Location $ProjectRoot
        $locationChanged = $true
    }

    Write-Host 'Ejecutando análisis estático...' -ForegroundColor Yellow
    Invoke-Flutter -Stage 'flutter analyze' -Arguments @('analyze')

    if ($UseSafeBuildPath) {
        Pop-Location
        $locationChanged = $false
        $FlutterExecutable = Join-Path $RunRoot '.tooling\flutter\bin\flutter.bat'
        Push-Location $RunRoot
        $locationChanged = $true
    }

    Write-Host 'Ejecutando pruebas...' -ForegroundColor Yellow
    Invoke-Flutter -Stage 'flutter test' -Arguments @('test')

    Write-Host 'Generando APK de depuración validada...' -ForegroundColor Yellow
    Invoke-Flutter -Stage 'flutter build apk --debug' -Arguments @(
        'build',
        'apk',
        '--debug',
        '--no-pub'
    )

    $apkPath = Join-Path $RunRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
        throw "Flutter finalizó sin crear la APK esperada: $apkPath"
    }

    Write-Host "APK validada: $(Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-debug.apk')" -ForegroundColor Green
}
catch {
    $primaryFailure = $_.Exception.Message
}
finally {
    if ($locationChanged) {
        try {
            Pop-Location
        }
        catch {
            $cleanupFailures.Add("No se pudo restaurar el directorio de trabajo: $($_.Exception.Message)")
        }
    }

    if ($safeDriveCreated) {
        try {
            $substCleanupOutput = & subst.exe $SafeBuildDrive /D 2>&1
            $substCleanupExitCode = $LASTEXITCODE
            if ($substCleanupExitCode -ne 0) {
                throw "subst devolvió código ${substCleanupExitCode}: $($substCleanupOutput -join ' ')"
            }
        }
        catch {
            $cleanupFailures.Add("No se pudo desmontar $SafeBuildDrive $($_.Exception.Message)")
        }

        try {
            $nativeAssetsCache = Join-Path $ProjectRoot '.dart_tool\hooks_runner'
            if (Test-Path -LiteralPath $nativeAssetsCache) {
                Remove-Item -LiteralPath $nativeAssetsCache -Recurse -Force
            }
        }
        catch {
            $cleanupFailures.Add("No se pudo limpiar el caché temporal de assets nativos: $($_.Exception.Message)")
        }

        # Restaura la configuración para seguir usando Flutter desde la ruta real.
        try {
            Push-Location $ProjectRoot
            try {
                Write-Host '> flutter pub get (restauración en la ruta real)' -ForegroundColor Cyan
                & $GlobalFlutterExecutable pub get
                $restoreExitCode = $LASTEXITCODE
                if ($restoreExitCode -ne 0) {
                    throw "flutter pub get devolvió código $restoreExitCode."
                }
            }
            finally {
                Pop-Location
            }
        }
        catch {
            $cleanupFailures.Add("No se pudo restaurar pub get en la ruta real: $($_.Exception.Message)")
        }
    }
}

if ($primaryFailure) {
    foreach ($cleanupFailure in $cleanupFailures) {
        Write-Warning $cleanupFailure
    }
    Write-Error -Message $primaryFailure -ErrorAction Continue
    exit 1
}

if ($cleanupFailures.Count -gt 0) {
    foreach ($cleanupFailure in $cleanupFailures) {
        Write-Warning $cleanupFailure
    }
    Write-Error -Message 'La validación terminó, pero falló la limpieza/restauración del entorno.' -ErrorAction Continue
    exit 1
}
