#!/bin/bash
set -e

WORK="/tmp/chumchim-build"
ISO_SRC="/mnt/c/Users/phanu/Downloads/clonezilla-live-3.2.2-5-amd64.iso"
CUSTOM_MENU="/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts/custom-menu.sh"
OUTPUT="/mnt/c/Images/chumchim-clonezilla.iso"

echo "=== Building ChumChim-Clonezilla ISO ==="

echo "[1/5] Extracting ISO..."
rm -rf $WORK
mkdir -p $WORK/iso $WORK/squashfs /mnt/cdrom
mount -o loop $ISO_SRC /mnt/cdrom
cp -a /mnt/cdrom/* $WORK/iso/
cp -a /mnt/cdrom/.disk $WORK/iso/ 2>/dev/null || true
umount /mnt/cdrom
echo "  OK"

echo "[2/5] Extracting filesystem..."
unsquashfs -d $WORK/squashfs $WORK/iso/live/filesystem.squashfs > /dev/null 2>&1
echo "  OK"

echo "[3/5] Injecting custom menu..."
cp $CUSTOM_MENU $WORK/squashfs/usr/local/bin/school-menu
chmod +x $WORK/squashfs/usr/local/bin/school-menu

cat > $WORK/squashfs/etc/profile.d/99-school-menu.sh << 'EOF'
if [ "$(tty)" = "/dev/tty1" ] && [ "$(whoami)" = "user" ]; then
    /usr/local/bin/school-menu
fi
EOF
chmod +x $WORK/squashfs/etc/profile.d/99-school-menu.sh
echo "  OK"

echo "[4/5] Modifying boot config..."
cat > $WORK/iso/boot/grub/grub.cfg << 'EOF'
set default="0"
set timeout="5"

menuentry "ChumChim-Clonezilla" {
  linux /live/vmlinuz boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us
  initrd /live/initrd.img
}

menuentry "Clonezilla (Original)" {
  linux /live/vmlinuz boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us
  initrd /live/initrd.img
}
EOF

cat > $WORK/iso/syslinux/syslinux.cfg << 'EOF'
DEFAULT school
TIMEOUT 50

LABEL school
  MENU LABEL ChumChim-Clonezilla
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components quiet username=user locales=en_US.UTF-8 keyboard-layouts=us

LABEL clonezilla
  MENU LABEL Clonezilla (Original)
  kernel /live/vmlinuz
  append initrd=/live/initrd.img boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=us
EOF
cp $WORK/iso/syslinux/syslinux.cfg $WORK/iso/syslinux/isolinux.cfg
echo "  OK"

echo "[5/5] Repacking + creating ISO..."
rm $WORK/iso/live/filesystem.squashfs
mksquashfs $WORK/squashfs $WORK/iso/live/filesystem.squashfs -comp xz -quiet

rm -f $OUTPUT
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "ChumChimClone" \
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
    -output $OUTPUT \
    $WORK/iso 2>&1 | tail -5

rm -rf $WORK

SIZE=$(du -h $OUTPUT | cut -f1)
echo ""
echo "========================================"
echo "  School Clonezilla ISO: $SIZE"
echo "  File: $OUTPUT"
echo "========================================"
