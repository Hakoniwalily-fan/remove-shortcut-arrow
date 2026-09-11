@echo off
chcp 65001 >nul
title Remove shortcut arrow

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Removing desktop shortcut arrow...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShortcutArrow.ps1" -Action Remove
echo.
echo Finished. Press any key to close.
pause >nul
