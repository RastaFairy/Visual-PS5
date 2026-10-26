@echo off
setlocal
set "BUNDLE_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BUNDLE_ROOT%runtime\Install-OfflineEnvironment.ps1" -BundleRoot "%BUNDLE_ROOT%" -Apply
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="3010" goto restart_required
if "%RESULT%"=="194" goto restart_required
if not "%RESULT%"=="0" (
  echo.
  echo La instalacion no termino. Revisa el diagnostico anterior y vuelve a ejecutar este archivo.
  pause
)
exit /b %RESULT%

:restart_required
echo.
echo Windows debe reiniciarse para continuar. Reinicia y vuelve a ejecutar este archivo.
pause
exit /b %RESULT%
