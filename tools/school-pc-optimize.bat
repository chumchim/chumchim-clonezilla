@echo off
title ChumChim - School PC Optimize
color 0A
echo.
echo  ============================================
echo    ChumChim - School PC Optimize
echo    Cleanup + Disable unnecessary services
echo    Run BEFORE cloning!
echo  ============================================
echo.
echo  This script will:
echo    - Clean temp files, cache, recycle bin
echo    - Disable hibernation + pagefile
echo    - Disable Windows Update
echo    - Disable Windows Defender real-time
echo    - Disable Search Indexing
echo    - Disable Cortana/Copilot
echo    - Disable OneDrive
echo    - Disable Telemetry
echo    - Disable Xbox/Game services
echo    - Disable unnecessary startup apps
echo.
pause

:: Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    echo Right-click ^> Run as Administrator
    pause
    exit /b 1
)

echo.
echo [1/10] Cleaning temp files...
del /q /s %TEMP%\* 2>nul
del /q /s C:\Windows\Temp\* 2>nul
del /q /s C:\Windows\Prefetch\* 2>nul
rd /s /q C:\Windows\SoftwareDistribution\Download 2>nul
mkdir C:\Windows\SoftwareDistribution\Download 2>nul
:: Empty Recycle Bin
rd /s /q C:\$Recycle.Bin 2>nul
:: Clean Windows Update cache
net stop wuauserv >nul 2>&1
del /q /s C:\Windows\SoftwareDistribution\DataStore\* 2>nul
net start wuauserv >nul 2>&1
echo   Done!

echo [2/10] Disabling hibernation...
powercfg /h off
echo   Done! (saved 4-16 GB)

echo [3/10] Disabling pagefile...
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
echo   Done! (saved 4-16 GB, takes effect after restart)

echo [4/10] Disabling Windows Update...
sc config wuauserv start= disabled >nul 2>&1
sc stop wuauserv >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
sc stop UsoSvc >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1
echo   Done!

echo [5/10] Disabling Windows Defender real-time...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
sc config WinDefend start= disabled >nul 2>&1
sc stop WinDefend >nul 2>&1
echo   Done!

echo [6/10] Disabling Search Indexing...
sc config WSearch start= disabled >nul 2>&1
sc stop WSearch >nul 2>&1
echo   Done!

echo [7/10] Disabling Cortana/Copilot...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >nul 2>&1
echo   Done!

echo [8/10] Disabling OneDrive...
taskkill /f /im OneDrive.exe >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f >nul 2>&1
if exist "%SystemRoot%\SysWOW64\OneDriveSetup.exe" (
    "%SystemRoot%\SysWOW64\OneDriveSetup.exe" /uninstall >nul 2>&1
) else if exist "%SystemRoot%\System32\OneDriveSetup.exe" (
    "%SystemRoot%\System32\OneDriveSetup.exe" /uninstall >nul 2>&1
)
echo   Done!

echo [9/10] Disabling Telemetry + Xbox...
:: Telemetry
sc config DiagTrack start= disabled >nul 2>&1
sc stop DiagTrack >nul 2>&1
sc config dmwappushservice start= disabled >nul 2>&1
sc stop dmwappushservice >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
:: Xbox
sc config XblAuthManager start= disabled >nul 2>&1
sc config XblGameSave start= disabled >nul 2>&1
sc config XboxGipSvc start= disabled >nul 2>&1
sc config XboxNetApiSvc start= disabled >nul 2>&1
echo   Done!

echo [10/10] Disabling unnecessary startup apps...
:: Disable common startup items
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Spotify" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Discord" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Steam" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Skype" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Teams" /f >nul 2>&1
:: Disable Startup delay
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v StartupDelayInMSec /t REG_DWORD /d 0 /f >nul 2>&1
echo   Done!

echo.
echo  ============================================
echo    OPTIMIZE COMPLETE!
echo  ============================================
echo.
echo  Summary:
echo    - Temp/cache cleaned
echo    - Hibernation OFF (saved 4-16 GB)
echo    - Pagefile OFF (saved 4-16 GB after restart)
echo    - Windows Update OFF
echo    - Defender real-time OFF
echo    - Search Indexing OFF
echo    - Cortana/Copilot OFF
echo    - OneDrive removed
echo    - Telemetry OFF
echo    - Xbox services OFF
echo    - Startup apps cleaned
echo.
echo  Next steps:
echo    1. Restart this PC
echo    2. Boot from ChumChim USB
echo    3. Clone this PC
echo.
echo  Total disk saved: ~10-50 GB
echo  PC will run faster for students!
echo.
pause
