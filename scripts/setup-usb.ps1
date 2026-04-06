#Requires -RunAsAdministrator
# ============================================
#   Setup School Clonezilla USB
#   1. Rufus สร้าง USB จาก Clonezilla ISO ก่อน
#   2. รัน script นี้ เพื่อใส่ custom menu
# ============================================

$ErrorActionPreference = 'Stop'

Clear-Host
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "    Setup School Clonezilla USB               " -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Before running this:" -ForegroundColor Yellow
Write-Host "    1. Download Clonezilla ISO" -ForegroundColor White
Write-Host "    2. Use Rufus to write ISO to USB" -ForegroundColor White
Write-Host "    3. Then run this script" -ForegroundColor White
Write-Host ""

# Find USB with Clonezilla
$usbDrive = $null
Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -or $_.FileSystemLabel -match 'Clonezilla|CLONEZILLA' } | ForEach-Object {
    $l = $_.DriveLetter
    if ($l -and (Test-Path "${l}:\live\vmlinuz" -ErrorAction SilentlyContinue)) {
        $usbDrive = $l
    }
}

if (-not $usbDrive) {
    # Try all removable drives
    Get-Volume | Where-Object { $_.DriveType -eq 'Removable' } | ForEach-Object {
        $l = $_.DriveLetter
        if ($l) { Write-Host "  Found: ${l}: $($_.FileSystemLabel)" -ForegroundColor Gray }
    }
    Write-Host ""
    $usbDrive = (Read-Host "  USB drive letter (e.g. D)").Trim().Replace(":","")
}

if (-not (Test-Path "${usbDrive}:\live" -ErrorAction SilentlyContinue)) {
    Write-Host "[X] Not a Clonezilla USB: ${usbDrive}:\" -ForegroundColor Red
    Write-Host "    Use Rufus to write Clonezilla ISO first" -ForegroundColor Yellow
    Read-Host "  Press Enter"
    exit 1
}

Write-Host "  USB: ${usbDrive}:\" -ForegroundColor Green
Write-Host ""

# ============================================
# Modify boot menu - auto-start our menu
# ============================================

Write-Host "  [1/3] Modifying boot menu..." -ForegroundColor Cyan

# Syslinux (Legacy BIOS)
$syslinuxCfg = "${usbDrive}:\syslinux\syslinux.cfg"
if (-not (Test-Path $syslinuxCfg)) { $syslinuxCfg = "${usbDrive}:\syslinux\isolinux.cfg" }

if (Test-Path $syslinuxCfg) {
    # Backup original
    Copy-Item $syslinuxCfg "$syslinuxCfg.bak" -Force

    @"
DEFAULT school
TIMEOUT 30
PROMPT 0

LABEL school
  MENU LABEL School Image Builder
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us ocs_live_run="/usr/local/bin/school-menu" ocs_live_batch="no" ocs_prerun="mount /dev/disk/by-label/YOURPARTLABEL /mnt" ocs_live_extra_param=""

LABEL clonezilla
  MENU LABEL Clonezilla (Original)
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us
"@ | Set-Content $syslinuxCfg -Encoding ASCII -Force
    Write-Host "         [OK] Syslinux config" -ForegroundColor Green
}

# GRUB (UEFI)
$grubCfg = "${usbDrive}:\boot\grub\grub.cfg"
if (Test-Path $grubCfg) {
    Copy-Item $grubCfg "$grubCfg.bak" -Force

    @"
set default=0
set timeout=3

menuentry "School Image Builder" {
  linux /live/vmlinuz boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us ocs_live_run="/usr/local/bin/school-menu" ocs_live_batch="no"
  initrd /live/initrd.img
}

menuentry "Clonezilla (Original)" {
  linux /live/vmlinuz boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us
  initrd /live/initrd.img
}
"@ | Set-Content $grubCfg -Encoding ASCII -Force
    Write-Host "         [OK] GRUB config" -ForegroundColor Green
}

# ============================================
# Copy custom menu script
# ============================================

Write-Host "  [2/3] Copying custom menu..." -ForegroundColor Cyan

# Create directory on USB for our script
$scriptDir = "${usbDrive}:\live\custom"
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

# Copy our menu script
$menuScript = "$PSScriptRoot\custom-menu.sh"
if (Test-Path $menuScript) {
    Copy-Item $menuScript "$scriptDir\school-menu.sh" -Force
    Write-Host "         [OK] Menu script copied" -ForegroundColor Green
} else {
    Write-Host "         [X] custom-menu.sh not found" -ForegroundColor Red
}

# ============================================
# Create auto-run hook
# ============================================

Write-Host "  [3/3] Setting up auto-run..." -ForegroundColor Cyan

# The script needs to be at /usr/local/bin/school-menu inside the live system
# Since we can't modify squashfs from Windows, we use ocs_live_run parameter
# which tells Clonezilla to run our script at boot
# We put the script on the USB and copy it at boot time

@"
#!/bin/bash
# Copy school menu from USB to system
for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
    mkdir -p /tmp/usbcheck
    mount \$dev /tmp/usbcheck 2>/dev/null
    if [ -f "/tmp/usbcheck/live/custom/school-menu.sh" ]; then
        cp /tmp/usbcheck/live/custom/school-menu.sh /usr/local/bin/school-menu
        chmod +x /usr/local/bin/school-menu
        umount /tmp/usbcheck
        /usr/local/bin/school-menu
        exit 0
    fi
    umount /tmp/usbcheck 2>/dev/null
done
echo "School menu not found!"
bash
"@ | Set-Content "$scriptDir\startup.sh" -Encoding UTF8 -Force

Write-Host "         [OK] Auto-run configured" -ForegroundColor Green

# ============================================
# Done
# ============================================

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "    USB Ready!                                " -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Boot from this USB to see:" -ForegroundColor Yellow
Write-Host "    School Image Builder" -ForegroundColor White
Write-Host "      [1] Capture this PC" -ForegroundColor Gray
Write-Host "      [2] Deploy image" -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter"
