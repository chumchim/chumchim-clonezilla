#!/bin/bash
set -e

# MUST build on WSL native filesystem, NOT /mnt/c/
BUILD_DIR="/root/chumchim-live"
WEBAPP_SRC="/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/webapp"
MENU_SRC="/mnt/c/Users/phanu/source/repos/chumchim-clonezilla/scripts"
OUTPUT="/mnt/c/Images/chumchim-clonezilla-v3.iso"

echo "=== Building ChumChim-Clonezilla v3.0 (Web UI) ==="
echo "    This will take 15-30 minutes..."
echo ""

# Cleanup
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# ============================================
# Configure live-build
# ============================================
echo "[1/5] Configuring..."

lb config \
    --distribution noble \
    --archive-areas "main universe" \
    --bootappend-live "boot=live components quiet" \
    --iso-volume "ChumChim" \
    --iso-application "ChumChim-Clonezilla" \
    --memtest none \
    2>/dev/null

# ============================================
# Package list
# ============================================
echo "[2/5] Setting package list..."

cat > config/package-lists/chumchim.list.chroot << 'EOF'
# Clonezilla tools
partclone
partimage
ntfs-3g
dosfstools
parted
gdisk
hdparm
sdparm
smartmontools
pigz
pbzip2
lz4
zstd

# Web UI
python3
chromium-browser
xinit
x11-xserver-utils
openbox
xdotool

# Network tools
dnsmasq
nfs-kernel-server
syslinux-common
pxelinux
udpcast
ethtool

# Filesystem
btrfs-progs
xfsprogs
f2fs-tools
hfsprogs
squashfs-tools

# Utilities
dialog
rsync
pv
bc
wget
curl
nano
less
ssh
EOF

# ============================================
# Custom files
# ============================================
echo "[3/5] Adding custom files..."

mkdir -p config/includes.chroot/opt/chumchim
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/etc/profile.d

# Web app
cp -r $WEBAPP_SRC/* config/includes.chroot/opt/chumchim/

# Dialog menu (fallback)
cp $MENU_SRC/custom-menu.sh config/includes.chroot/usr/local/bin/school-menu
chmod +x config/includes.chroot/usr/local/bin/school-menu

# Multicast
cp $MENU_SRC/multicast-server.sh config/includes.chroot/usr/local/bin/ 2>/dev/null || true

# Auto-start script
cat > config/includes.chroot/etc/profile.d/99-chumchim.sh << 'STARTEOF'
if [ "$(tty)" = "/dev/tty1" ]; then
    # Start web server
    python3 /opt/chumchim/server.py &
    SERVER_PID=$!
    sleep 2

    if command -v chromium-browser >/dev/null 2>&1; then
        # Web UI mode
        xinit /usr/bin/chromium-browser \
            --no-sandbox \
            --kiosk \
            --disable-gpu \
            --disable-software-rasterizer \
            --disable-dev-shm-usage \
            --no-first-run \
            --disable-translate \
            --disable-extensions \
            http://localhost:8080 \
            -- :0 2>/dev/null

        kill $SERVER_PID 2>/dev/null
    else
        # Fallback to dialog
        kill $SERVER_PID 2>/dev/null
        /usr/local/bin/school-menu
    fi
fi
STARTEOF
chmod +x config/includes.chroot/etc/profile.d/99-chumchim.sh

# Auto-login on tty1
mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d
cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'LOGINEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
LOGINEOF

# ============================================
# Build
# ============================================
echo "[4/5] Building ISO (this takes 15-30 min)..."

lb build 2>&1 | grep -E "^P:|^I:|Setting up|Building|Creating" | head -50

# ============================================
# Output
# ============================================
echo "[5/5] Saving ISO..."

ISO_FILE=$(ls *.iso 2>/dev/null | head -1)
if [ -n "$ISO_FILE" ]; then
    cp "$ISO_FILE" "$OUTPUT"
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo ""
    echo "========================================"
    echo "  ChumChim-Clonezilla v3.0: $SIZE"
    echo "  File: $OUTPUT"
    echo "========================================"
else
    echo "[X] Build failed!"
    echo "Check logs in $BUILD_DIR/build.log"
    ls -la $BUILD_DIR/
fi
