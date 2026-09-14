@echo off
chcp 65001 >nul
title Verify shortcut arrow state

echo ShortcutArrow diagnostic - read-only, changes nothing.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShortcutArrow.ps1" -Action Verify
echo.
echo Finished. Press any key to close.
pause >nul
