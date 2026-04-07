@echo off
title Fix Shrink - Step 1: Disable + Restart
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

if exist "C:\shrink-step2.flag" goto :STEP2

echo.
echo  ============================================
echo    STEP 1: Disable unmovable files
echo  ============================================
echo.
echo  Disabling hibernation...
powercfg /hibernate off
echo  Disabling System Restore...
powershell -Command "Disable-ComputerRestore -Drive 'C:\'" 2>nul
echo  Disabling pagefile...
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
echo  Done!
echo.

:: Mark for step 2 after restart
echo step2 > "C:\shrink-step2.flag"

:: Set this script to run on next boot
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "ShrinkStep2" /t REG_SZ /d "\"%~f0\"" /f >nul 2>&1

echo  ============================================
echo    Restarting in 10 seconds...
echo    After restart, shrink will run automatically!
echo  ============================================
shutdown /r /t 10 /f
exit /b

:STEP2
echo.
echo  ============================================
echo    STEP 2: Defrag + Shrink (after restart)
echo  ============================================
echo.
del "C:\shrink-step2.flag" 2>nul

echo  Defragmenting...
defrag C: /U /V /X >nul 2>&1
echo  Done!

echo  Shrinking partition...
powershell -ExecutionPolicy Bypass -File "%~dp0shrink-partition.ps1"

echo.
echo  ============================================
echo    SHRINK COMPLETE!
echo  ============================================
echo.
echo  Now you can Clone this PC.
echo  Boot from ChumChim USB and select Clone.
echo.
pause
