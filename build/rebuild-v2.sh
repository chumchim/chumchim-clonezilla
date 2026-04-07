#!/bin/bash
set -e

WORK=/root/v2-build
ISO_SRC=/mnt/c/Users/phanu/Downloads/clonezilla-live-3.2.2-5-amd64.iso
SCRIPTS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts
OUTPUT=/mnt/c/Images/chumchim-clonezilla.iso

echo "=== Building ChumChim v3.0 ==="

rm -rf $WORK
mkdir -p $WORK/iso $WORK/squashfs /mnt/cdrom

echo "[1/5] Extracting ISO..."
mount -o loop $ISO_SRC /mnt/cdrom
cp -a /mnt/cdrom/* $WORK/iso/
cp -a /mnt/cdrom/.disk $WORK/iso/ 2>/dev/null || true
umount /mnt/cdrom

echo "[2/5] Extracting squashfs..."
unsquashfs -d $WORK/squashfs $WORK/iso/live/filesystem.squashfs > /dev/null 2>&1

echo "[3/5] Injecting scripts..."
cp $SCRIPTS/custom-menu.sh $WORK/squashfs/usr/local/bin/school-menu
chmod +x $WORK/squashfs/usr/local/bin/school-menu
cp $SCRIPTS/multicast-server.sh $WORK/squashfs/usr/local/bin/ 2>/dev/null || true
cp $SCRIPTS/lan-server.sh $WORK/squashfs/usr/local/bin/ 2>/dev/null || true
chmod +x $WORK/squashfs/usr/local/bin/lan-server.sh 2>/dev/null || true

# Disable Clonezilla's own auto-start
rm -f $WORK/squashfs/etc/profile.d/*ocs* 2>/dev/null
rm -f $WORK/squashfs/etc/profile.d/*clonezilla* 2>/dev/null
# Disable ocs-live-run-menu if it exists
if [ -f "$WORK/squashfs/usr/sbin/ocs-live-run-menu" ]; then
    echo '#!/bin/sh' > $WORK/squashfs/usr/sbin/ocs-live-run-menu
    echo 'exit 0' >> $WORK/squashfs/usr/sbin/ocs-live-run-menu
    chmod +x $WORK/squashfs/usr/sbin/ocs-live-run-menu
fi
# Disable Clonezilla systemd service
rm -f $WORK/squashfs/etc/systemd/system/multi-user.target.wants/ocs-live.service 2>/dev/null || true
ln -sf /dev/null $WORK/squashfs/etc/systemd/system/ocs-live.service 2>/dev/null || true

# Sudoers for auto-partition and school-menu
echo "user ALL=(ALL) NOPASSWD: ALL" > $WORK/squashfs/etc/sudoers.d/chumchim
chmod 0440 $WORK/squashfs/etc/sudoers.d/chumchim

# Auto-create data partition on boot USB if unallocated space exists
cat > $WORK/squashfs/usr/local/bin/auto-partition.sh << 'PARTEOF'
#!/bin/bash
# Find the boot USB device by label or by scanning
BOOT_DEV=""
# Try label first (fast)
LABEL_DEV=$(blkid -L "ChumChimV3" 2>/dev/null)
if [ -n "$LABEL_DEV" ]; then
    BOOT_DEV=$(echo "$LABEL_DEV" | sed 's/[0-9]*$//;s/p[0-9]*$//')
else
    # Fallback: scan for /live directory
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        [ -b "$dev" ] || continue
        mkdir -p /tmp/_bp 2>/dev/null
        mount -o ro "$dev" /tmp/_bp 2>/dev/null || continue
        if [ -d "/tmp/_bp/live" ]; then
            BOOT_DEV=$(echo "$dev" | sed 's/[0-9]*$//;s/p[0-9]*$//')
            umount /tmp/_bp 2>/dev/null
            break
        fi
        umount /tmp/_bp 2>/dev/null
    done
    rmdir /tmp/_bp 2>/dev/null
fi
[ -z "$BOOT_DEV" ] && exit 0

# Check if there's unallocated space (>1GB) on boot USB
DISK_SIZE_MB=$(blockdev --getsize64 "$BOOT_DEV" 2>/dev/null)
[ -z "$DISK_SIZE_MB" ] && exit 0
DISK_SIZE_MB=$((DISK_SIZE_MB / 1048576))

USED_MB=0
for part in ${BOOT_DEV}[0-9]* ${BOOT_DEV}p[0-9]*; do
    [ -b "$part" ] || continue
    PSIZE=$(blockdev --getsize64 "$part" 2>/dev/null)
    [ -n "$PSIZE" ] && USED_MB=$((USED_MB + PSIZE / 1048576))
done

FREE_MB=$((DISK_SIZE_MB - USED_MB))
[ "$FREE_MB" -lt 1024 ] && exit 0

# Check if data partition already exists (look for NTFS/ext4 partition > 1GB)
for part in ${BOOT_DEV}[0-9]* ${BOOT_DEV}p[0-9]*; do
    [ -b "$part" ] || continue
    FS=$(blkid -o value -s TYPE "$part" 2>/dev/null)
    PSIZE=$(($(blockdev --getsize64 "$part" 2>/dev/null) / 1048576))
    if [ "$PSIZE" -gt 1024 ] && { [ "$FS" = "ntfs" ] || [ "$FS" = "ext4" ] || [ "$FS" = "vfat" ]; }; then
        exit 0  # Data partition already exists
    fi
done

# Create new partition in unallocated space
echo "Creating data partition on $BOOT_DEV (~${FREE_MB}MB)..."
echo -e "n\np\n\n\n\nw" | fdisk "$BOOT_DEV" 2>/dev/null
sleep 2
partprobe "$BOOT_DEV" 2>/dev/null
sleep 1

# Find the new partition (last one)
NEW_PART=$(ls ${BOOT_DEV}[0-9]* ${BOOT_DEV}p[0-9]* 2>/dev/null | sort -V | tail -1)
if [ -b "$NEW_PART" ]; then
    echo "Formatting $NEW_PART as ext4..."
    mkfs.ext4 -F -L "ChumChimData" "$NEW_PART" 2>/dev/null
    echo "Data partition ready: $NEW_PART"
fi
PARTEOF
chmod +x $WORK/squashfs/usr/local/bin/auto-partition.sh

# Auto-start ChumChim menu (with auto-partition first)
cat > $WORK/squashfs/etc/profile.d/99-chumchim.sh << 'EOF'
if [ "$(tty)" = "/dev/tty1" ] && [ "$(whoami)" = "user" ]; then
    # Auto-create data partition if needed
    sudo /usr/local/bin/auto-partition.sh 2>/dev/null
    /usr/local/bin/school-menu
fi
EOF
chmod +x $WORK/squashfs/etc/profile.d/99-chumchim.sh

echo "[4/5] Modifying boot config..."
# GRUB (UEFI)
cat > $WORK/iso/boot/grub/grub.cfg << 'EOF'
search --no-floppy --label --set=root ChumChimV3
search --no-floppy --file --set=root /live/vmlinuz
set default="0"
set timeout="5"
menuentry "ChumChim-Clonezilla v3.0" {
  linux /live/vmlinuz boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us
  initrd /live/initrd.img
}
menuentry "ChumChim text mode" {
  linux /live/vmlinuz boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us textonly
  initrd /live/initrd.img
}
EOF

# Syslinux (BIOS/Legacy)
cat > $WORK/iso/syslinux/syslinux.cfg << 'EOF'
DEFAULT ChumChim
PROMPT 0
TIMEOUT 50

UI vesamenu.c32
MENU TITLE ChumChim-Clonezilla v3.0
MENU BACKGROUND ocswp.png

LABEL ChumChim
  MENU LABEL ChumChim-Clonezilla v3.0
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us

LABEL ChumChim-text
  MENU LABEL ChumChim text mode
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us textonly
EOF
cp $WORK/iso/syslinux/syslinux.cfg $WORK/iso/syslinux/isolinux.cfg

echo "[5/6] Adding docs + tools to ISO root..."
DOCS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/docs
TOOLS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/tools
cp $DOCS/*.txt $WORK/iso/ 2>/dev/null || true
mkdir -p $WORK/iso/tools
cp $TOOLS/*.bat $WORK/iso/tools/ 2>/dev/null || true
echo "  OK"

echo "[6/6] Repacking ISO..."
rm $WORK/iso/live/filesystem.squashfs
mksquashfs $WORK/squashfs $WORK/iso/live/filesystem.squashfs -comp zstd -Xcompression-level 3 -quiet

rm -f $OUTPUT
xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -volid "ChumChimV3" \
    -eltorito-boot syslinux/isolinux.bin -eltorito-catalog syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
    -output $OUTPUT $WORK/iso 2>&1 | tail -3

rm -rf $WORK

if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo ""
    echo "========================================"
    echo "  ChumChim: $SIZE"
    echo "  File: $OUTPUT"
    echo "========================================"
else
    echo "[X] Failed"
fi
