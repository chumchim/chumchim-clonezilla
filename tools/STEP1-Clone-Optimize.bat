@echo off
title [CLONE] Optimize + Shrink for Cloning
color 0E
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

echo.
echo  ============================================
echo    CLONE PC: Optimize + Shrink
echo    Run this on the PC you want to CLONE (PC-B)
echo    Before booting ChumChim USB
echo  ============================================
echo.
echo  This will:
echo    - Clean temp/cache
echo    - Disable unnecessary services
echo    - Remove bloatware
echo    - Shrink partition (smaller image)
echo.
echo  After done, shutdown PC then boot USB
echo  and select "1 Clone this PC"
echo.
pause

echo.
echo  [1/5] Cleaning temp + cache...
del /q /s "%TEMP%\*" 2>nul
del /q /s "C:\Windows\Temp\*" 2>nul
rd /s /q "C:\$Recycle.Bin" 2>nul
rd /s /q "C:\Windows.old" 2>nul
echo  Done!

echo  [2/5] Disabling services + pagefile + hibernation...
powercfg /hibernate off
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
powershell -Command "Disable-ComputerRestore -Drive 'C:\'" 2>nul
for %%s in (wuauserv UsoSvc WSearch DiagTrack XblAuthManager XblGameSave XboxGipSvc XboxNetApiSvc) do (
    sc config %%s start= disabled >nul 2>&1
    sc stop %%s >nul 2>&1
)
sc config WinDefend start= disabled >nul 2>&1
rd /s /q "C:\ProgramData\Microsoft\Windows Defender\Definition Updates" 2>nul
vssadmin delete shadows /for=C: /all /quiet >nul 2>&1
echo  Done!

echo  [3/5] Removing bloatware...
powershell -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -match 'BingWeather|BingNews|CandyCrush|Disney|Spotify|TikTok|Netflix|Roblox|McAfee|Norton|Clipchamp|Xbox|GamingApp|Solitaire|Widgets|Chat'} | Remove-AppxPackage -ErrorAction SilentlyContinue" 2>nul
echo  Done!

echo  [4/5] Compact OS...
compact /compactos:always >nul 2>&1
echo  Done!

echo  [5/5] Shrinking C: partition...
powershell -Command "$min=(Get-PartitionSupportedSize -DriveLetter C).SizeMin; $used=[math]::Round((Get-PSDrive C).Used/1GB); $target=[math]::Max(($used+30)*1GB, $min+10GB); Write-Host \"  Used: ${used}GB Min: $([math]::Round($min/1GB))GB Target: $([math]::Round($target/1GB))GB\"; Resize-Partition -DriveLetter C -Size $target -ErrorAction Stop; Write-Host \"  Partition now: $([math]::Round((Get-Partition -DriveLetter C).Size/1GB))GB\" -ForegroundColor Green"
if %errorlevel% neq 0 (
    echo.
    echo  Shrink failed! Need restart first.
    echo  Restarting in 10 seconds...
    echo  After restart, run this script again.
    shutdown /r /t 10 /f
    exit /b
)

echo.
echo  ============================================
echo    CLONE PC OPTIMIZE COMPLETE!
echo  ============================================
echo.
echo  NEXT: Shutdown PC then boot ChumChim USB
echo        Select "1 Clone this PC"
echo.
echo  Shutting down in 30 seconds...
echo  Press any key to shutdown NOW.
pause
shutdown /s /t 5 /f
