@echo off
title ChumChim - School PC Optimize v2
color 0A
echo.
echo  ============================================
echo    ChumChim - School PC Optimize v2
echo    Cleanup + Optimize + Shrink for Clone
echo    Run BEFORE cloning!
echo  ============================================
echo.
echo  This script will:
echo    Phase 1: Clean temp files, cache, recycle bin
echo    Phase 2: Disable unnecessary services
echo    Phase 3: Remove bloatware apps
echo    Phase 4: Cleanup system components
echo    Phase 5: Shrink partition (HUGE speed boost!)
echo    Phase 6: Zero-fill free space (better compression)
echo.
echo  Estimated savings: 20-70 GB
echo  Clone will be MUCH faster after this!
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
echo ====== PHASE 1: CLEANUP (saves 10-30 GB) ======
echo.

echo [1/6] Cleaning temp files + cache...
del /q /s "%TEMP%\*" 2>nul
del /q /s "C:\Windows\Temp\*" 2>nul
del /q /s "C:\Windows\Prefetch\*" 2>nul
:: Windows Update cache
net stop wuauserv >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution\Download" 2>nul
mkdir "C:\Windows\SoftwareDistribution\Download" 2>nul
del /q /s "C:\Windows\SoftwareDistribution\DataStore\*" 2>nul
:: Recycle Bin
rd /s /q "C:\$Recycle.Bin" 2>nul
:: Thumbnail cache
del /q /s "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*" 2>nul
:: Windows Error Reports
rd /s /q "C:\ProgramData\Microsoft\Windows\WER" 2>nul
:: Delivery Optimization cache
del /q /s "C:\Windows\SoftwareDistribution\DeliveryOptimization\*" 2>nul
echo   Done!

echo [2/6] Disabling hibernation...
powercfg /h off
echo   Done! (saved 4-16 GB)

echo [3/6] Disabling pagefile...
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
:: Delete pagefile on disk
del /f /q "C:\pagefile.sys" 2>nul
del /f /q "C:\swapfile.sys" 2>nul
echo   Done! (saved 4-16 GB)

echo.
echo ====== PHASE 2: DISABLE SERVICES ======
echo.

echo [4/6] Disabling unnecessary services...
:: Windows Update
sc config wuauserv start= disabled >nul 2>&1
sc stop wuauserv >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
sc stop UsoSvc >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1

:: Windows Defender real-time
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
sc config WinDefend start= disabled >nul 2>&1
sc stop WinDefend >nul 2>&1

:: Search Indexing
sc config WSearch start= disabled >nul 2>&1
sc stop WSearch >nul 2>&1

:: Cortana/Copilot
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >nul 2>&1

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

:: OneDrive
taskkill /f /im OneDrive.exe >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f >nul 2>&1
if exist "%SystemRoot%\SysWOW64\OneDriveSetup.exe" (
    "%SystemRoot%\SysWOW64\OneDriveSetup.exe" /uninstall >nul 2>&1
) else if exist "%SystemRoot%\System32\OneDriveSetup.exe" (
    "%SystemRoot%\System32\OneDriveSetup.exe" /uninstall >nul 2>&1
)

:: Startup apps
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Spotify" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Discord" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Steam" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Skype" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Teams" /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v StartupDelayInMSec /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable System Restore
vssadmin delete shadows /for=C: /all /quiet >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" /v DisableSR /t REG_DWORD /d 1 /f >nul 2>&1

echo   Done!

echo.
echo ====== PHASE 3: REMOVE BLOATWARE (saves 2-8 GB) ======
echo.

echo [5/6] Removing pre-installed apps...
powershell -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -match 'BingWeather|BingNews|BingFinance|BingSports|CandyCrush|Disney|Dolby|Facebook|Flipboard|Spotify|Twitter|TikTok|Netflix|Roblox|McAfee|Norton|ExpressVPN|Clipchamp|LinkedInforWindows|MicrosoftTeams|Todos|MicrosoftOfficeHub|MixedReality|Paint3D|Print3D|3DBuilder|3DViewer|People|Skype|Solitaire|Zune|Xbox|GamingApp|MicrosoftStickyNotes|WindowsMaps|WindowsFeedbackHub|GetHelp|Getstarted|YourPhone|WindowsAlarms|WindowsSoundRecorder|WindowsCamera|MicrosoftNews|PowerAutomate|QuickAssist|Family'} | Remove-AppxPackage -ErrorAction SilentlyContinue" 2>nul
powershell -Command "Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -match 'BingWeather|BingNews|CandyCrush|Disney|Dolby|Facebook|Spotify|Twitter|TikTok|Netflix|Roblox|McAfee|Norton|Clipchamp|Teams|Todos|OfficeHub|MixedReality|Paint3D|Print3D|3DBuilder|3DViewer|People|Skype|Solitaire|Zune|Xbox|GamingApp|StickyNotes|Maps|FeedbackHub|GetHelp|Getstarted|YourPhone|Alarms|SoundRecorder|News|PowerAutomate|QuickAssist|Family'} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue" 2>nul
echo   Done!

echo.
echo ====== PHASE 4: SYSTEM CLEANUP (saves 2-8 GB) ======
echo.

echo [6/6] Cleaning system components...
:: WinSxS cleanup (old component versions)
dism /online /Cleanup-Image /StartComponentCleanup /ResetBase >nul 2>&1
:: Remove unused Windows features
dism /online /disable-feature /featurename:Windows-Defender-Default-Definitions /norestart >nul 2>&1
dism /online /disable-feature /featurename:Printing-XPSServices-Features /norestart >nul 2>&1
dism /online /disable-feature /featurename:WorkFolders-Client /norestart >nul 2>&1
:: Run Windows Disk Cleanup silently
cleanmgr /d C /sagerun:1 >nul 2>&1
echo   Done!

echo.
echo ====== PHASE 5: SHRINK PARTITION ======
echo.

echo  Shrinking C: partition to fit data + 20%% buffer...
echo  This makes Clone MUCH faster!
echo.

:: Get current usage and shrink
powershell -Command ^
  "$drive = Get-PSDrive C; ^
   $usedGB = [math]::Round(($drive.Used)/1GB); ^
   $freeGB = [math]::Round(($drive.Free)/1GB); ^
   $totalGB = $usedGB + $freeGB; ^
   $targetGB = [math]::Round($usedGB * 1.3); ^
   $shrinkMB = [math]::Round(($totalGB - $targetGB) * 1024); ^
   Write-Host \"  Current: ${totalGB}GB (Used: ${usedGB}GB, Free: ${freeGB}GB)\"; ^
   Write-Host \"  Target:  ${targetGB}GB (Used + 30%% buffer)\"; ^
   Write-Host \"  Shrink:  ${shrinkMB}MB\"; ^
   if ($shrinkMB -gt 1024) { ^
     Write-Host '  Shrinking...' -ForegroundColor Yellow; ^
     $size = (Get-Partition -DriveLetter C).Size - ($shrinkMB * 1MB); ^
     Resize-Partition -DriveLetter C -Size $size -ErrorAction SilentlyContinue; ^
     Write-Host '  Done!' -ForegroundColor Green; ^
   } else { ^
     Write-Host '  Partition already small enough, skipping.' -ForegroundColor Green; ^
   }"
echo.

echo.
echo ====== PHASE 6: ZERO-FILL FREE SPACE ======
echo.

echo  Zero-filling free space for better compression...
echo  This may take a few minutes...
echo.
:: cipher /w zeros out free space in 3 passes
cipher /w:C >nul 2>&1
echo   Done!

echo.
echo  ============================================
echo    ALL OPTIMIZATION COMPLETE!
echo  ============================================
echo.
echo  What was done:
echo    [Phase 1] Temp/cache/pagefile/hibernation cleaned
echo    [Phase 2] Unnecessary services disabled
echo    [Phase 3] Bloatware apps removed
echo    [Phase 4] System components cleaned
echo    [Phase 5] C: partition shrunk to fit data
echo    [Phase 6] Free space zero-filled
echo.
echo  Estimated total savings: 20-70 GB
echo  Clone image will be MUCH smaller and faster!
echo.
echo  Next steps:
echo    1. Restart this PC
echo    2. (Optional) Run school-pc-sysprep.bat
echo    3. Boot from ChumChim USB
echo    4. Clone this PC
echo.
pause
