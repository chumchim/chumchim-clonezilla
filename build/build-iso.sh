#!/bin/bash
# ============================================
#   Build custom School Clonezilla ISO
#   Run on Linux (or WSL)
# ============================================

set -e

WORK_DIR="/tmp/school-clonezilla-build"
CLONEZILLA_ISO="clonezilla-live-3.1.0-22-amd64.iso"
CLONEZILLA_URL="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.1.0-22/$CLONEZILLA_ISO/download"
OUTPUT_ISO="school-clonezilla.iso"

echo "============================================"
echo "  Building School Clonezilla ISO"
echo "============================================"

# Step 1: Download Clonezilla if not exists
if [ ! -f "$CLONEZILLA_ISO" ]; then
    echo "[1] Downloading Clonezilla..."
    wget -O "$CLONEZILLA_ISO" "$CLONEZILLA_URL"
fi

# Step 2: Extract ISO
echo "[2] Extracting ISO..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/iso" "$WORK_DIR/squashfs"

mount -o loop "$CLONEZILLA_ISO" /mnt
cp -a /mnt/* "$WORK_DIR/iso/"
umount /mnt

# Step 3: Extract squashfs
echo "[3] Extracting filesystem..."
unsquashfs -d "$WORK_DIR/squashfs" "$WORK_DIR/iso/live/filesystem.squashfs"

# Step 4: Inject custom menu script
echo "[4] Injecting custom menu..."
cp scripts/custom-menu.sh "$WORK_DIR/squashfs/usr/local/bin/school-menu"
chmod +x "$WORK_DIR/squashfs/usr/local/bin/school-menu"

# Make it auto-start
cat > "$WORK_DIR/squashfs/etc/profile.d/school-menu.sh" << 'EOF'
# Auto-start School menu on login
if [ "$(tty)" = "/dev/tty1" ]; then
    /usr/local/bin/school-menu
fi
EOF

# Step 5: Modify boot menu
echo "[5] Modifying boot menu..."
cat > "$WORK_DIR/iso/syslinux/isolinux.cfg" << 'EOF'
DEFAULT school
TIMEOUT 30
PROMPT 0

LABEL school
  MENU LABEL School Image Builder
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us ocs_live_run="/usr/local/bin/school-menu" ocs_live_batch="no"
EOF

# UEFI boot
cat > "$WORK_DIR/iso/boot/grub/grub.cfg" << 'EOF'
set default=0
set timeout=3

menuentry "School Image Builder" {
  linux /live/vmlinuz boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us ocs_live_run="/usr/local/bin/school-menu" ocs_live_batch="no"
  initrd /live/initrd.img
}
EOF

# Step 6: Repack squashfs
echo "[6] Repacking filesystem..."
rm "$WORK_DIR/iso/live/filesystem.squashfs"
mksquashfs "$WORK_DIR/squashfs" "$WORK_DIR/iso/live/filesystem.squashfs" -comp xz

# Step 7: Create ISO
echo "[7] Creating ISO..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "SchoolClone" \
    -eltorito-boot syslinux/isolinux.bin \
    -eltorito-catalog syslinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output "$OUTPUT_ISO" \
    "$WORK_DIR/iso"

echo ""
echo "============================================"
echo "  ISO Created: $OUTPUT_ISO"
echo "  Size: $(du -h $OUTPUT_ISO | cut -f1)"
echo "============================================"
echo ""
echo "  Use Rufus to write to USB"

# Cleanup
rm -rf "$WORK_DIR"
