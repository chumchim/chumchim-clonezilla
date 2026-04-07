@echo off
title ChumChim - School PC Optimize v3
color 0A
echo.
echo  ============================================
echo    ChumChim - School PC Optimize v3
echo    Cleanup + Optimize + Shrink + School Setup
echo    Run BEFORE cloning!
echo  ============================================
echo.
echo  Phase 1: Clean temp/cache/junk files
echo  Phase 2: Disable unnecessary services
echo  Phase 3: Remove bloatware apps
echo  Phase 4: System cleanup + Compact OS
echo  Phase 5: School environment setup
echo  Phase 6: Defragment + Shrink partition
echo  Phase 7: Zero-fill free space
echo.
echo  Estimated savings: 30-80 GB
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
echo ====== PHASE 1: CLEANUP (saves 15-40 GB) ======
echo.

echo [1/10] Cleaning temp files + cache...
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
rd /s /q "C:\Windows\SoftwareDistribution\DeliveryOptimization" 2>nul
:: Windows old (from upgrades)
rd /s /q "C:\Windows.old" 2>nul
rd /s /q "C:\$WINDOWS.~BT" 2>nul
rd /s /q "C:\$WINDOWS.~WS" 2>nul
:: Installer cache
del /q /s "C:\Windows\Installer\$PatchCache$\*" 2>nul
:: Font cache
net stop FontCache >nul 2>&1
del /q /s "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache\*" 2>nul
net start FontCache >nul 2>&1
echo   Done!

echo [2/10] Disabling hibernation + pagefile + swapfile...
powercfg /h off
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
del /f /q "C:\pagefile.sys" 2>nul
del /f /q "C:\swapfile.sys" 2>nul
del /f /q "C:\hiberfil.sys" 2>nul
echo   Done! (saved 8-32 GB)

echo.
echo ====== PHASE 2: DISABLE SERVICES ======
echo.

echo [3/10] Disabling unnecessary services...
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
:: Delete Defender definitions (1-2 GB)
rd /s /q "C:\ProgramData\Microsoft\Windows Defender\Definition Updates" 2>nul

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

:: System Restore
vssadmin delete shadows /for=C: /all /quiet >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" /v DisableSR /t REG_DWORD /d 1 /f >nul 2>&1

echo   Done!

echo.
echo ====== PHASE 3: REMOVE BLOATWARE (saves 2-8 GB) ======
echo.

echo [4/10] Removing pre-installed apps...
powershell -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -match 'BingWeather|BingNews|BingFinance|BingSports|CandyCrush|Disney|Dolby|Facebook|Flipboard|Spotify|Twitter|TikTok|Netflix|Roblox|McAfee|Norton|ExpressVPN|Clipchamp|LinkedInforWindows|MicrosoftTeams|Todos|MicrosoftOfficeHub|MixedReality|Paint3D|Print3D|3DBuilder|3DViewer|People|Skype|Solitaire|Zune|Xbox|GamingApp|MicrosoftStickyNotes|WindowsMaps|WindowsFeedbackHub|GetHelp|Getstarted|YourPhone|WindowsAlarms|WindowsSoundRecorder|WindowsCamera|MicrosoftNews|PowerAutomate|QuickAssist|Family|Widgets|Chat'} | Remove-AppxPackage -ErrorAction SilentlyContinue" 2>nul
powershell -Command "Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -match 'BingWeather|BingNews|CandyCrush|Disney|Dolby|Facebook|Spotify|Twitter|TikTok|Netflix|Roblox|McAfee|Norton|Clipchamp|Teams|Todos|OfficeHub|MixedReality|Paint3D|Print3D|3DBuilder|3DViewer|People|Skype|Solitaire|Zune|Xbox|GamingApp|StickyNotes|Maps|FeedbackHub|GetHelp|Getstarted|YourPhone|Alarms|SoundRecorder|News|PowerAutomate|QuickAssist|Family|Widgets|Chat'} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue" 2>nul
echo   Done!

echo.
echo ====== PHASE 4: SYSTEM CLEANUP + COMPACT OS (saves 5-15 GB) ======
echo.

echo [5/10] Cleaning system components...
:: WinSxS cleanup
dism /online /Cleanup-Image /StartComponentCleanup /ResetBase >nul 2>&1
:: Remove unused Windows features
dism /online /disable-feature /featurename:Windows-Defender-Default-Definitions /norestart >nul 2>&1
dism /online /disable-feature /featurename:Printing-XPSServices-Features /norestart >nul 2>&1
dism /online /disable-feature /featurename:WorkFolders-Client /norestart >nul 2>&1
dism /online /disable-feature /featurename:FaxServicesClientPackage /norestart >nul 2>&1
dism /online /disable-feature /featurename:MediaPlayback /norestart >nul 2>&1
:: Disk Cleanup
cleanmgr /d C /sagerun:1 >nul 2>&1
echo   Done!

echo [6/10] Enabling Compact OS (compress Windows files)...
echo   This saves 5-10 GB. Windows still works normally.
compact /compactos:always >nul 2>&1
echo   Done!

echo.
echo ====== PHASE 5: SCHOOL ENVIRONMENT SETUP ======
echo.

echo [7/10] Configuring for school use...

:: Power settings: never sleep, never turn off screen
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /setactive SCHEME_MIN >nul 2>&1

:: Desktop: show useful icons
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" /t REG_DWORD /d 0 /f >nul 2>&1

:: Show file extensions
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable lock screen
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable first login animation
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableFirstLogonAnimation /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable tips/suggestions/ads
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable Widgets
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1

:: Taskbar: clean up
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f >nul 2>&1

:: Set timezone to Thailand
tzutil /s "SE Asia Standard Time" >nul 2>&1

:: Set languages: English (US) + Thai
powershell -Command "$l = New-WinUserLanguageList en-US; $t = New-WinUserLanguageList th-TH; $l.Add($t[0]); Set-WinUserLanguageList $l -Force" 2>nul
:: Set system locale to Thai (for Thai app support)
powershell -Command "Set-WinSystemLocale th-TH" 2>nul
:: Set region to Thailand
powershell -Command "Set-WinHomeLocation -GeoId 227" 2>nul
:: Set date/time format to Thai
powershell -Command "Set-Culture th-TH" 2>nul

:: Disable USB autoplay (security)
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" /v DisableAutoplay /t REG_DWORD /d 1 /f >nul 2>&1

:: Disable remote desktop (security)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 1 /f >nul 2>&1

echo   Done!

echo.
echo ====== PHASE 6: DEFRAGMENT + SHRINK PARTITION ======
echo.

echo [8/10] Defragmenting C: drive...
echo   This helps shrink partition further...
defrag C: /O /U >nul 2>&1
echo   Done!

echo [9/10] Shrinking C: partition...
echo   This makes Clone MUCH faster!
echo $d=Get-PSDrive C;$u=[math]::Round($d.Used/1GB);$f=[math]::Round($d.Free/1GB);$t=$u+$f;$g=[math]::Round($u*1.3);$s=[math]::Round(($t-$g)*1024);Write-Host "  Current: ${t}GB (Used: ${u}GB, Free: ${f}GB)";Write-Host "  Target: ${g}GB";if($s -gt 1024){Write-Host "  Shrinking ${s}MB...";$sz=(Get-Partition -DriveLetter C).Size-($s*1MB);Resize-Partition -DriveLetter C -Size $sz -ErrorAction SilentlyContinue;Write-Host "  Done!"}else{Write-Host "  Already small enough"} > "%TEMP%\shrink.ps1"
powershell -ExecutionPolicy Bypass -File "%TEMP%\shrink.ps1" 2>nul
del "%TEMP%\shrink.ps1" 2>nul
echo.

echo.
echo ====== PHASE 7: ZERO-FILL FREE SPACE ======
echo.

echo [10/10] Zero-filling free space...
echo   This makes clone image MUCH smaller.
echo   May take 5-10 minutes...
cipher /w:C >nul 2>&1
echo   Done!

echo.
echo  ============================================
echo    ALL OPTIMIZATION COMPLETE!
echo  ============================================
echo.
echo  What was done:
echo    [Phase 1] Temp, cache, pagefile, hibernation cleaned
echo    [Phase 2] Unnecessary services disabled
echo    [Phase 3] Bloatware apps removed
echo    [Phase 4] System cleanup + Compact OS enabled
echo    [Phase 5] School environment configured
echo              - Languages: English (US) + Thai
echo              - Thailand timezone, region, date format
echo              - No lock screen, no ads, no tips
echo              - Clean taskbar, useful desktop icons
echo              - USB autoplay disabled (security)
echo    [Phase 6] Defragmented + partition shrunk
echo    [Phase 7] Free space zero-filled
echo.
echo  Next steps:
echo    1. (Optional) Run school-pc-sysprep.bat
echo       (Sysprep will shutdown PC automatically)
echo    2. Or shutdown manually then boot USB to Clone
echo.
pause
