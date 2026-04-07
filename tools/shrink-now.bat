@echo off
title Shrink Partition
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)
echo Shrinking C: partition...
powershell -ExecutionPolicy Bypass -File "%~dp0shrink-partition.ps1"
echo.
pause
