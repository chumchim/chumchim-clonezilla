#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

$vmName = "SchoolPC-LTSC"
$vhdxPath = "C:\Hyper-V\$vmName\$vmName.vhdx"
$isoPath = "C:\Images\Win10-LTSC.iso"

Write-Host "=== Recreating School PC VM ===" -ForegroundColor Cyan

# Cleanup
Stop-VM -Name $vmName -Force -TurnOff -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Hyper-V\$vmName" -Recurse -Force -ErrorAction SilentlyContinue

# Create VHDX
Write-Host "[1/5] Creating disk..."
New-Item -ItemType Directory -Path "C:\Hyper-V\$vmName" -Force | Out-Null
New-VHD -Path $vhdxPath -SizeBytes 60GB -Dynamic | Out-Null

# Mount + partition
Write-Host "[2/5] Partitioning..."
Mount-VHD -Path $vhdxPath
$disk = Get-Disk | Where-Object { $_.Location -eq $vhdxPath }
Initialize-Disk -Number $disk.Number -PartitionStyle GPT

$efiPart = New-Partition -DiskNumber $disk.Number -Size 260MB -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
Format-Volume -Partition $efiPart -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false | Out-Null
$efiPart | Add-PartitionAccessPath -AssignDriveLetter
Start-Sleep 2

New-Partition -DiskNumber $disk.Number -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" | Out-Null

$winPart = New-Partition -DiskNumber $disk.Number -UseMaximumSize
Format-Volume -Partition $winPart -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
$winPart | Add-PartitionAccessPath -AssignDriveLetter
Start-Sleep 2

$efiLetter = (Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Size -lt 300MB -and $_.Size -gt 200MB -and $_.DriveLetter }).DriveLetter
$winLetter = (Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Basic" -and $_.Size -gt 1GB }).DriveLetter
Write-Host "  EFI=$efiLetter  WIN=$winLetter"

# Apply Windows
Write-Host "[3/5] Installing Windows 10 LTSC..."
$mount = Mount-DiskImage -ImagePath $isoPath -PassThru
$isoLetter = ($mount | Get-Volume).DriveLetter
$img = if (Test-Path "${isoLetter}:\sources\install.wim") { "${isoLetter}:\sources\install.wim" }
       elseif (Test-Path "${isoLetter}:\sources\install.esd") { "${isoLetter}:\sources\install.esd" }

DISM /Apply-Image /ImageFile:"$img" /Index:1 /ApplyDir:"${winLetter}:\" /Quiet
Write-Host "  DISM: $LASTEXITCODE"

Dismount-DiskImage -ImagePath $isoPath | Out-Null

# Fix boot using Win10's own bcdboot
Write-Host "[4/5] Fixing boot..."
$bcdboot = "${winLetter}:\Windows\System32\bcdboot.exe"
if (Test-Path $bcdboot) {
    & $bcdboot "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI
    Write-Host "  bcdboot (Win10): $LASTEXITCODE"
} else {
    # Fallback to host bcdboot
    bcdboot "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI
    Write-Host "  bcdboot (host): $LASTEXITCODE"
}

# Inject unattend + scripts (same as before)
Write-Host "[5/5] Injecting setup..."
New-Item -ItemType Directory -Path "${winLetter}:\Windows\Panther" -Force | Out-Null

$unattend = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>Student</Name>
            <Group>Administrators</Group>
            <Password>
              <Value></Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>Student</Username>
        <Password>
          <Value></Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>999</LogonCount>
      </AutoLogon>
      <TimeZone>SE Asia Standard Time</TimeZone>
    </component>
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>0409:00000409;041E:0000041E</InputLocale>
      <SystemLocale>th-TH</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>th-TH</UserLocale>
    </component>
  </settings>
</unattend>
"@
$unattend | Set-Content "${winLetter}:\Windows\Panther\unattend.xml" -Encoding UTF8

# Disable BitLocker
reg load "HKLM\OFFLINE" "${winLetter}:\Windows\System32\config\SYSTEM" 2>$null | Out-Null
reg add "HKLM\OFFLINE\ControlSet001\Control\BitLocker" /v "PreventDeviceEncryption" /t REG_DWORD /d 1 /f 2>$null | Out-Null
reg unload "HKLM\OFFLINE" 2>$null | Out-Null

# Inject post-install script
New-Item -ItemType Directory -Path "${winLetter}:\Scripts" -Force | Out-Null
if (Test-Path "C:\Users\phanu\source\repos\school-image-builder\tools\software\install-office.ps1") {
    Copy-Item "C:\Users\phanu\source\repos\school-image-builder\tools\software\install-office.ps1" "${winLetter}:\Scripts\" -Force
}

# Copy post-install script
Copy-Item "$PSScriptRoot\post-install.ps1" "${winLetter}:\Scripts\post-install.ps1" -Force

# Register to run on first boot
reg load "HKLM\OFFLINE_SW" "${winLetter}:\Windows\System32\config\SOFTWARE" 2>$null | Out-Null
reg add "HKLM\OFFLINE_SW\Microsoft\Windows\CurrentVersion\RunOnce" /v "PostInstall" /t REG_SZ /d "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Scripts\post-install.ps1" /f 2>$null | Out-Null
reg unload "HKLM\OFFLINE_SW" 2>$null | Out-Null

Dismount-VHD -Path $vhdxPath
Start-Sleep 2

# Create VM
$sw = (Get-VMSwitch | Select-Object -First 1).Name
New-VM -Name $vmName -MemoryStartupBytes 4GB -Generation 2 -VHDPath $vhdxPath -Path "C:\Hyper-V" -SwitchName $sw | Out-Null
Set-VM -Name $vmName -ProcessorCount 4 -CheckpointType Disabled
Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
$hdd = Get-VMHardDiskDrive -VMName $vmName
Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd
Start-VM -Name $vmName

Write-Host ""
Write-Host "=== VM READY ===" -ForegroundColor Green
Write-Host "  Name: $vmName"
Write-Host "  Windows 10 Enterprise LTSC"
Write-Host "  Auto: OOBE skip, Student login, Office, Optimize, UWF"
Write-Host "  Wait ~15-20 min for post-install to complete"
