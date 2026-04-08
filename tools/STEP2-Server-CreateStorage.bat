@echo off
title [SERVER] Create Storage Partition
color 0B
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

echo.
echo  ============================================
echo    SERVER: Create Storage Partition
echo    Run AFTER shrink on the SERVER PC
echo  ============================================
echo.
echo  This will create a new partition from
echo  unallocated space for storing clone images.
echo.
pause

echo.
echo  Finding NVMe/SSD disk...
powershell -ExecutionPolicy Bypass -Command "$disks = Get-Disk | Where-Object { $_.PartitionStyle -ne 'RAW' -and $_.Size -gt 50GB }; foreach ($d in $disks) { $free = $d.Size - ($d | Get-Partition | Measure-Object Size -Sum).Sum; $freeGB = [math]::Round($free/1GB); if ($freeGB -gt 10) { Write-Host \"  Disk $($d.Number): $($d.FriendlyName) - $freeGB GB unallocated\"; Write-Host \"  Creating partition...\"; $p = New-Partition -DiskNumber $d.Number -UseMaximumSize -AssignDriveLetter; Format-Volume -DriveLetter $p.DriveLetter -FileSystem exFAT -NewFileSystemLabel 'ImageStore' -Confirm:$false | Out-Null; Write-Host \"  Created: $($p.DriveLetter): $([math]::Round($p.Size/1GB))GB (ImageStore)\" -ForegroundColor Green; exit } }; Write-Host '  No unallocated space found!' -ForegroundColor Red; Write-Host '  Run STEP1-Server-Shrink.bat first'"

echo.
echo  ============================================
echo    DONE! Now shutdown and boot ChumChim USB
echo    Select "3 LAN Server"
echo  ============================================
echo.
pause
shutdown /s /t 5 /f
