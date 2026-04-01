@echo off
setlocal

set "PSHOST=powershell.exe"
where pwsh.exe >nul 2>nul && set "PSHOST=pwsh.exe"

"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ImageConverter.ps1" %*
exit /b %errorlevel%
