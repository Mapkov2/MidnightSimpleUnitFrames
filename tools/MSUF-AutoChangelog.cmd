@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSUF-AutoChangelog.ps1" -Watch -RegenerateAddonChangelog %*
