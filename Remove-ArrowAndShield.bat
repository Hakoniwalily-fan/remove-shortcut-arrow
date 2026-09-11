@echo off
chcp 65001 >nul
title Remove shortcut arrow and UAC shield

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Removing shortcut arrow AND UAC shield overlay...
echo.
echo NOTE: hiding the shield only hides the warning icon.
echo       Programs that need admin still raise a UAC prompt.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShortcutArrow.ps1" -Action Remove -IncludeShield
echo.
echo Finished. Press any key to close.
pause >nul
