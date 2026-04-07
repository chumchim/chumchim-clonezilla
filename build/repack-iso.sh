#!/bin/bash
set -e
OUTPUT=/mnt/c/Images/chumchim-v3.iso
WORK=/root/v3-build

xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -volid "ChumChimV3" \
    -eltorito-boot syslinux/isolinux.bin -eltorito-catalog syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
    -output $OUTPUT $WORK/iso 2>&1 | tail -5

if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo ""
    echo "========================================"
    echo "  ChumChim v3.0: $SIZE"
    echo "  File: $OUTPUT"
    echo "========================================"
else
    echo "[X] Failed"
fi
