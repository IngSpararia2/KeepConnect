@echo off
setlocal
cd /d "%~dp0"

echo ========================================
echo   Actualizacion de APK - KeepConnect
echo ========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\actualizar_apk.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo APK actualizada correctamente.
) else (
    echo La actualizacion fallo con el codigo %EXIT_CODE%.
)
echo.
pause
exit /b %EXIT_CODE%
