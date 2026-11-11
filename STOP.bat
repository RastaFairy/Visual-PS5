@echo off
setlocal
echo Deteniendo PS5 Homebrew Studio…
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'powershell%'\" | Where-Object { $_.CommandLine -match 'server\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo Servidor detenido.
endlocal
