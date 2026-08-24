[CmdletBinding()]
param(
    # Omite las pruebas automatizadas, por ejemplo cuando solo necesitas una APK urgente.
    [switch]$SkipTests,
    # Mantiene los artefactos de Gradle para una compilación posterior más rápida.
    [switch]$ReutilizarCache
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$GradleWrapper = Join-Path $ProjectRoot 'android\gradlew.bat'
$UseSafeBuildPath = $ProjectRoot -match '\s'
# Cada ejecución recibe una unión propia. Si una compilación anterior se
# interrumpe, su carpeta temporal ya no bloquea actualizaciones posteriores.
$SafeBuildPath = Join-Path $env:SystemDrive "KeepConnectApkBuild-$([guid]::NewGuid().ToString('N'))"
$RunRoot = $ProjectRoot
$junctionCreated = $false
$locationChanged = $false
$scriptFailed = $false
$failureMessage = $null

function Invoke-Flutter {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Write-Host ("> flutter " + ($Arguments -join ' ')) -ForegroundColor Cyan
    & flutter @Arguments
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

    # Flutter 3.44 puede fallar al invocar herramientas nativas desde rutas con espacios.
    # La unión temporal conserva el proyecto real y solo ofrece una ruta de compilación segura.
    if ($UseSafeBuildPath) {
        $mklinkOutput = & cmd.exe /d /c "mklink /J `"$SafeBuildPath`" `"$ProjectRoot`"" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo crear la unión temporal para compilar: $($mklinkOutput -join ' ')"
        }
        $junctionCreated = $true
        $RunRoot = $SafeBuildPath
    }

    Push-Location $RunRoot
    $locationChanged = $true

    Write-Host 'Verificando Flutter y el Android SDK...' -ForegroundColor Yellow
    $doctor = & flutter doctor -v 2>&1
    $doctorExit = $LASTEXITCODE
    $doctor | ForEach-Object { Write-Host $_ }
    $doctorText = $doctor | Out-String
    if ($doctorExit -ne 0 -or $doctorText -match '(?m)^\s*\[(X|✗)\]\s+Android toolchain') {
        throw 'El Android SDK/JDK no está listo. Corrige el apartado Android toolchain de "flutter doctor -v" y vuelve a ejecutar.'
    }

    if (-not $ReutilizarCache) {
        Write-Host 'Limpiando la compilación anterior...' -ForegroundColor Yellow
        Invoke-Flutter -Arguments @('clean')
    }

    Write-Host 'Sincronizando dependencias...' -ForegroundColor Yellow
    Invoke-Flutter -Arguments @('pub', 'get')
    Invoke-Flutter -Arguments @('analyze')

    if (-not $SkipTests) {
        Invoke-Flutter -Arguments @('test')
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

    if ($junctionCreated) {
        Remove-Item -LiteralPath $SafeBuildPath -Force
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
