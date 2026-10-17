@echo off
setlocal
cd /d "%~dp0"
title PS5 Homebrew Studio
set "PSHOST=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PSHOST=pwsh.exe"
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\check-syntax.ps1"
if errorlevel 1 goto failed
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\server.ps1"
if errorlevel 1 goto failed
goto end
:failed
echo.
echo PS5 Homebrew Studio no pudo iniciar. Revisa los errores anteriores.
pause
:end
endlocal
