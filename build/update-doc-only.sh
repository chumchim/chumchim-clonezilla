#!/bin/bash
set -e

WORK=/root/doc-update
ISO_SRC=/mnt/c/Images/chumchim-clonezilla.iso
DOCS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/docs
OUTPUT=/mnt/c/Images/chumchim-clonezilla-new.iso

echo "=== Updating docs in ISO (fast) ==="

rm -rf $WORK
mkdir -p $WORK/iso /mnt/cdrom

echo "[1/3] Extracting ISO..."
mount -o loop $ISO_SRC /mnt/cdrom
cp -a /mnt/cdrom/* $WORK/iso/
cp -a /mnt/cdrom/.disk $WORK/iso/ 2>/dev/null || true
umount /mnt/cdrom

echo "[2/3] Updating docs..."
cp $DOCS/*.txt $WORK/iso/ 2>/dev/null || true
ls $WORK/iso/*.txt 2>/dev/null

echo "[3/3] Repacking ISO (no squashfs rebuild)..."
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
    echo "Done! $SIZE -> $OUTPUT"
    echo "Run: mv chumchim-clonezilla-new.iso chumchim-clonezilla.iso"
fi
