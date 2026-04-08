@echo off
title [SERVER] Shrink Partition for LAN Server
color 0B
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

echo.
echo  ============================================
echo    SERVER: Shrink Partition
echo    Run this on the SERVER PC
echo    Before booting ChumChim USB
echo  ============================================
echo.
pause

echo.
echo  [1/2] Disabling pagefile + hibernation...
powercfg /hibernate off
wmic computersystem set AutomaticManagedPagefile=False >nul 2>&1
wmic pagefileset delete >nul 2>&1
powershell -Command "Disable-ComputerRestore -Drive 'C:\'" 2>nul
echo  Done!

echo.
echo  [2/2] Shrinking C: partition (auto-size)...
powershell -Command "$used=[math]::Round((Get-PSDrive C).Used/1GB); $min=(Get-PartitionSupportedSize -DriveLetter C).SizeMin; $target=[math]::Max(($used+20)*1GB, $min+5GB); Write-Host \"  Used: ${used}GB\"; Write-Host \"  Target: $([math]::Round($target/1GB))GB\"; try { Resize-Partition -DriveLetter C -Size $target -ErrorAction Stop; Write-Host \"  OK! Now: $([math]::Round((Get-Partition -DriveLetter C).Size/1GB))GB\" -ForegroundColor Green } catch { Write-Host \"  Failed: $_\" -ForegroundColor Red; Write-Host \"  Restart PC then run again.\" -ForegroundColor Yellow; pause; shutdown /r /t 5 /f; exit }"

echo.
echo  ============================================
echo    SHRINK COMPLETE!
echo  ============================================
echo.
echo  Shutting down... then boot USB
echo  Select "3 LAN Server"
echo.
pause
shutdown /s /t 5 /f
