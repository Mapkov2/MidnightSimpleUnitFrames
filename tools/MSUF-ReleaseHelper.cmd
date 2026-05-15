@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSUF-ReleaseHelper.ps1"
endlocal
