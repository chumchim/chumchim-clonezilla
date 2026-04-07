#!/bin/bash
set -e

WORK=/root/v3-build
ISO_SRC=/mnt/c/Users/phanu/Downloads/clonezilla-live-3.2.2-5-amd64.iso
WEBAPP=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/webapp
SCRIPTS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts
OUTPUT=/mnt/c/Images/chumchim-v3.iso

echo "=== Building ChumChim v3.0 ==="

rm -rf $WORK
mkdir -p $WORK/iso $WORK/squashfs /mnt/cdrom

echo "[1/6] Extracting ISO..."
mount -o loop $ISO_SRC /mnt/cdrom
cp -a /mnt/cdrom/* $WORK/iso/
cp -a /mnt/cdrom/.disk $WORK/iso/ 2>/dev/null || true
umount /mnt/cdrom
echo "  OK"

echo "[2/6] Extracting filesystem..."
unsquashfs -d $WORK/squashfs $WORK/iso/live/filesystem.squashfs > /dev/null 2>&1
echo "  OK"

echo "[3/6] Installing browser + X11..."
mount --bind /dev $WORK/squashfs/dev
mount --bind /proc $WORK/squashfs/proc
mount --bind /sys $WORK/squashfs/sys
cp /etc/resolv.conf $WORK/squashfs/etc/resolv.conf

chroot $WORK/squashfs bash -c "
apt-get update -qq
apt-get install -y -qq python3 xinit x11-xserver-utils openbox firefox-esr dialog xserver-xorg-video-fbdev xserver-xorg-video-vesa xserver-xorg-video-all xserver-xorg-input-all 2>/dev/null
" 2>&1 | tail -3

umount $WORK/squashfs/sys
umount $WORK/squashfs/proc
umount $WORK/squashfs/dev
echo "  OK"

echo "[4/6] Injecting Web UI..."
mkdir -p $WORK/squashfs/opt/chumchim
cp -r $WEBAPP/* $WORK/squashfs/opt/chumchim/
cp $SCRIPTS/custom-menu.sh $WORK/squashfs/usr/local/bin/school-menu
chmod +x $WORK/squashfs/usr/local/bin/school-menu
cp $SCRIPTS/multicast-server.sh $WORK/squashfs/usr/local/bin/ 2>/dev/null || true

cat > $WORK/squashfs/etc/profile.d/99-chumchim.sh << 'EOF'
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
EOF
chmod +x $WORK/squashfs/etc/profile.d/99-chumchim.sh
echo "  OK"

echo "[5/6] Modifying boot config..."
# GRUB (UEFI)
cat > $WORK/iso/boot/grub/grub.cfg << 'EOF'
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
echo "  OK"

echo "[6/7] Adding docs to ISO root..."
DOCS=/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/docs
cp $DOCS/*.txt $WORK/iso/ 2>/dev/null || true
echo "  OK"

echo "[7/7] Repacking ISO..."
rm $WORK/iso/live/filesystem.squashfs
mksquashfs $WORK/squashfs $WORK/iso/live/filesystem.squashfs -comp xz -quiet

rm -f $OUTPUT
xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -volid "ChumChimV3" \
    -eltorito-boot syslinux/isolinux.bin -eltorito-catalog syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
    -output $OUTPUT $WORK/iso 2>&1 | tail -5

rm -rf $WORK

if [ -f $OUTPUT ]; then
    SIZE=$(du -h $OUTPUT | cut -f1)
    echo ""
    echo "========================================"
    echo "  ChumChim v3.0: $SIZE"
    echo "  File: $OUTPUT"
    echo "========================================"
else
    echo "[X] Failed"
fi
