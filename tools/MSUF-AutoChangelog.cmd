@echo off
setlocal
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSUF-AutoChangelog.ps1" -Gui
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSUF-AutoChangelog.ps1" %*
)
