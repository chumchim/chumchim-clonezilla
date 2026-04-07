#!/bin/bash
# Copy everything to WSL native filesystem and build there
set -e

echo "Copying sources to WSL filesystem..."
rm -rf /root/chumchim-build
mkdir -p /root/chumchim-build

cp -r /mnt/c/Users/phanu/source/repos/chumchim-clonezilla/webapp /root/chumchim-build/webapp
cp -r /mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts /root/chumchim-build/scripts
echo "OK"

echo "Setting up build..."
BUILD_DIR="/root/chumchim-live"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR
cd $BUILD_DIR

lb config \
    --distribution noble \
    --archive-areas "main universe" \
    --bootappend-live "boot=live components quiet" \
    --iso-volume "ChumChim" \
    --memtest none \
    --bootloaders "grub-efi" \
    --binary-images iso-hybrid

# Package list
cat > config/package-lists/chumchim.list.chroot << 'EOF'
partclone
partimage
ntfs-3g
dosfstools
parted
gdisk
smartmontools
pigz
lz4
python3
chromium-browser
xinit
x11-xserver-utils
openbox
dnsmasq
nfs-kernel-server
dialog
rsync
pv
nano
EOF

# Custom files
mkdir -p config/includes.chroot/opt/chumchim
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d

cp -r /root/chumchim-build/webapp/* config/includes.chroot/opt/chumchim/
cp /root/chumchim-build/scripts/custom-menu.sh config/includes.chroot/usr/local/bin/school-menu
chmod +x config/includes.chroot/usr/local/bin/school-menu

# Auto-start
cat > config/includes.chroot/etc/profile.d/99-chumchim.sh << 'SEOF'
if [ "$(tty)" = "/dev/tty1" ]; then
    python3 /opt/chumchim/server.py &
    sleep 2
    if command -v chromium-browser >/dev/null 2>&1; then
        xinit /usr/bin/chromium-browser --no-sandbox --kiosk --disable-gpu --disable-software-rasterizer --no-first-run http://localhost:8080 -- :0 2>/dev/null
    else
        /usr/local/bin/school-menu
    fi
fi
SEOF

# Auto-login
cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'LEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
LEOF

echo "Building ISO..."
lb build 2>&1

ISO=$(ls *.iso 2>/dev/null | head -1)
if [ -n "$ISO" ]; then
    cp "$ISO" /mnt/c/Images/chumchim-clonezilla-v3.iso
    SIZE=$(du -h /mnt/c/Images/chumchim-clonezilla-v3.iso | cut -f1)
    echo ""
    echo "========================================"
    echo "  ChumChim v3.0: $SIZE"
    echo "========================================"
else
    echo "BUILD FAILED"
    ls -la $BUILD_DIR/
fi
