@echo off
rem HelixSR setup: builds the network and frame generation, then installs HelixSR into your games (see helixsr-setup.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0helixsr-setup.ps1" %*
set "rc=%errorlevel%"
pause
exit /b %rc%
