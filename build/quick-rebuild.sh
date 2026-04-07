#!/bin/bash
set -e

WORK=/root/v3-build
ISO_SRC=/mnt/c/Images/chumchim-v3.iso
SCRIPTS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts
WEBAPP=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/webapp
OUTPUT=/mnt/c/Images/chumchim-v3-new.iso

echo "=== Quick rebuild ChumChim v3.0 ==="

rm -rf $WORK
mkdir -p $WORK/iso $WORK/squashfs /mnt/cdrom

echo "[1/5] Extracting ISO..."
mount -o loop $ISO_SRC /mnt/cdrom
cp -a /mnt/cdrom/* $WORK/iso/
cp -a /mnt/cdrom/.disk $WORK/iso/ 2>/dev/null || true
umount /mnt/cdrom

echo "[2/5] Extracting squashfs..."
unsquashfs -d $WORK/squashfs $WORK/iso/live/filesystem.squashfs > /dev/null 2>&1

echo "[3/5] Updating menu script..."
cp $SCRIPTS/custom-menu.sh $WORK/squashfs/usr/local/bin/school-menu
chmod +x $WORK/squashfs/usr/local/bin/school-menu

echo "[4/5] Updating autostart..."
cat > $WORK/squashfs/etc/profile.d/99-chumchim.sh << 'AUTOEOF'
if [ "$(tty)" = "/dev/tty1" ] && [ "$(whoami)" = "user" ]; then
    # Always start web server
    python3 /opt/chumchim/server.py &
    SERVER_PID=$!
    sleep 1

    # Load framebuffer module for VMs (Hyper-V, VirtualBox, etc.)
    modprobe hyperv_fb 2>/dev/null
    modprobe vboxvideo 2>/dev/null
    modprobe bochs-drm 2>/dev/null
    sleep 1

    LAUNCHED=false
    if command -v firefox-esr >/dev/null 2>&1 && command -v xinit >/dev/null 2>&1; then
        # Try to start X11 + Firefox in background
        xinit /usr/bin/firefox-esr --kiosk http://localhost:8080 -- :0 vt1 2>/dev/null &
        X_PID=$!
        sleep 5

        if kill -0 $X_PID 2>/dev/null; then
            LAUNCHED=true
            wait $X_PID
            kill $SERVER_PID 2>/dev/null
        fi
    fi

    if [ "$LAUNCHED" = "false" ]; then
        # X11 failed - show Web UI URL + fallback to dialog
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        echo "========================================="
        echo "  ChumChim-Clonezilla v3.0"
        if [ -n "$IP" ]; then
            echo "  Web UI: http://${IP}:8080"
        fi
        echo "  (Browser failed - using text mode)"
        echo "========================================="
        echo ""
        /usr/local/bin/school-menu
    fi
fi
AUTOEOF
chmod +x $WORK/squashfs/etc/profile.d/99-chumchim.sh

echo "[5/5] Repacking..."
rm $WORK/iso/live/filesystem.squashfs
mksquashfs $WORK/squashfs $WORK/iso/live/filesystem.squashfs -comp xz -quiet

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
    echo "  ChumChim v3.0: $SIZE"
    echo "  File: $OUTPUT"
    echo "========================================"
else
    echo "[X] Failed"
fi
