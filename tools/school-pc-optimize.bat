@echo off
title ChumChim - School PC Optimize v4
color 0A

:: Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

:: Marker file to track what's done
set MARKER=C:\ChumChim-Optimized.flag

if exist "%MARKER%" (
    echo.
    echo  ============================================
    echo    Already optimized! Running FAST mode
    echo    Only: Cleanup + Shrink + Zero-fill
    echo  ============================================
    echo.
    goto :FAST_MODE
)

echo.
echo  ============================================
echo    ChumChim - School PC Optimize v4
echo    First run: Full optimization
echo  ============================================
echo.
pause

echo.
echo ====== [1/10] Cleaning temp + cache ======
del /q /s "%TEMP%\*" 2>nul
del /q /s "C:\Windows\Temp\*" 2>nul
del /q /s "C:\Windows\Prefetch\*" 2>nul
net stop wuauserv >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution\Download" 2>nul
mkdir "C:\Windows\SoftwareDistribution\Download" 2>nul
rd /s /q "C:\$Recycle.Bin" 2>nul
rd /s /q "C:\ProgramData\Microsoft\Windows\WER" 2>nul
rd /s /q "C:\Windows.old" 2>nul
rd /s /q "C:\$WINDOWS.~BT" 2>nul
echo   Done!

echo ====== [2/10] Disabling hibernation + pagefile ======
powercfg /h off
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
echo   Done!

echo ====== [3/10] Disabling services ======
for %%s in (wuauserv UsoSvc WSearch DiagTrack dmwappushservice XblAuthManager XblGameSave XboxGipSvc XboxNetApiSvc) do (
    sc config %%s start= disabled >nul 2>&1
    sc stop %%s >nul 2>&1
)
sc config WinDefend start= disabled >nul 2>&1
sc stop WinDefend >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
rd /s /q "C:\ProgramData\Microsoft\Windows Defender\Definition Updates" 2>nul
taskkill /f /im OneDrive.exe >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f >nul 2>&1
vssadmin delete shadows /for=C: /all /quiet >nul 2>&1
echo   Done!

echo ====== [4/10] Removing bloatware ======
powershell -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -match 'BingWeather|BingNews|CandyCrush|Disney|Dolby|Facebook|Spotify|Twitter|TikTok|Netflix|Roblox|McAfee|Norton|Clipchamp|MicrosoftTeams|Todos|MicrosoftOfficeHub|MixedReality|Paint3D|3DBuilder|3DViewer|People|Skype|Solitaire|Zune|Xbox|GamingApp|StickyNotes|WindowsMaps|WindowsFeedbackHub|GetHelp|Getstarted|YourPhone|WindowsAlarms|WindowsSoundRecorder|MicrosoftNews|PowerAutomate|QuickAssist|Family|Widgets|Chat'} | Remove-AppxPackage -ErrorAction SilentlyContinue" 2>nul
echo   Done!

echo ====== [5/10] System cleanup + Compact OS ======
echo   WinSxS cleanup (may take a few minutes)...
dism /online /Cleanup-Image /StartComponentCleanup /ResetBase >nul 2>&1
echo   Enabling Compact OS...
compact /compactos:always >nul 2>&1
echo   Done!

echo ====== [6/10] School environment ======
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableFirstLogonAnimation /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1
tzutil /s "SE Asia Standard Time" >nul 2>&1
powershell -Command "$l = New-WinUserLanguageList en-US; $t = New-WinUserLanguageList th-TH; $l.Add($t[0]); Set-WinUserLanguageList $l -Force" 2>nul
powershell -Command "Set-WinSystemLocale th-TH" 2>nul
powershell -Command "Set-WinHomeLocation -GeoId 227" 2>nul
echo   Done!

:: Mark as optimized
echo %date% %time% > "%MARKER%"

:FAST_MODE

echo ====== [7/10] Cleaning temp (quick) ======
del /q /s "%TEMP%\*" 2>nul
del /q /s "C:\Windows\Temp\*" 2>nul
rd /s /q "C:\$Recycle.Bin" 2>nul
echo   Done!

echo ====== [8/10] Defragment ======
defrag C: /O /U >nul 2>&1
echo   Done!

echo ====== [9/10] Shrink partition ======
echo $d=Get-PSDrive C;$u=[math]::Round($d.Used/1GB);$f=[math]::Round($d.Free/1GB);$t=$u+$f;$g=[math]::Round($u*1.3);$s=[math]::Round(($t-$g)*1024);Write-Host "  Current: ${t}GB (Used: ${u}GB, Free: ${f}GB)";Write-Host "  Target: ${g}GB";if($s -gt 1024){Write-Host "  Shrinking ${s}MB...";$sz=(Get-Partition -DriveLetter C).Size-($s*1MB);Resize-Partition -DriveLetter C -Size $sz -ErrorAction SilentlyContinue;Write-Host "  Done!"}else{Write-Host "  Already small enough"} > "%TEMP%\shrink.ps1"
powershell -ExecutionPolicy Bypass -File "%TEMP%\shrink.ps1" 2>nul
del "%TEMP%\shrink.ps1" 2>nul
echo   Done!

echo ====== [10/10] Zero-fill ======
powershell -ExecutionPolicy Bypass -File "%~dp0zero-fill.ps1" 2>nul
del /f /q C:\zero.tmp 2>nul
echo   Done!

echo.
echo  ============================================
echo    OPTIMIZATION COMPLETE!
echo  ============================================
echo.
echo  Next: Run school-pc-sysprep.bat (auto-shutdown)
echo        Or shutdown manually then boot USB to Clone
echo.
pause
