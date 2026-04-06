#!/bin/bash
# ============================================
#   ChumChim Multicast Server
#   Deploy image to many PCs via LAN
# ============================================

LOG_FILE="/tmp/chumchim-multicast.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> $LOG_FILE
    echo "  $1"
}

# ============================================
# Detect network
# ============================================

detect_network() {
    # Find the LAN interface
    NET_IF=""
    NET_IP=""
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        IP=$(ip -4 addr show $iface 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$IP" ]; then
            NET_IF=$iface
            NET_IP=$IP
            break
        fi
    done

    if [ -z "$NET_IF" ]; then
        # Try to get IP via DHCP
        echo "  Getting IP from router..."
        for iface in $(ls /sys/class/net/ | grep -v lo); do
            dhclient $iface 2>/dev/null
            IP=$(ip -4 addr show $iface 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
            if [ -n "$IP" ]; then
                NET_IF=$iface
                NET_IP=$IP
                break
            fi
        done
    fi

    if [ -z "$NET_IF" ]; then
        echo "  [X] No network found! Connect LAN cable."
        return 1
    fi

    # Get subnet info
    NET_MASK=$(ip -4 addr show $NET_IF | grep inet | awk '{print $2}' | head -1)
    NET_GW=$(ip route | grep default | awk '{print $3}' | head -1)
    NET_SUBNET=$(echo $NET_IP | sed 's/\.[0-9]*$/.0/')

    echo "  Interface: $NET_IF"
    echo "  IP:        $NET_IP"
    echo "  Gateway:   $NET_GW"
    echo "  Subnet:    $NET_SUBNET"
    return 0
}

# ============================================
# Setup ProxyDHCP + TFTP
# ============================================

setup_pxe_server() {
    echo "  Setting up PXE server..."

    # Create TFTP root
    TFTP_ROOT="/tmp/tftpboot"
    mkdir -p $TFTP_ROOT/pxelinux.cfg

    # Copy PXE boot files
    if [ -f /usr/lib/PXELINUX/pxelinux.0 ]; then
        cp /usr/lib/PXELINUX/pxelinux.0 $TFTP_ROOT/
    elif [ -f /usr/lib/syslinux/modules/bios/pxelinux.0 ]; then
        cp /usr/lib/syslinux/modules/bios/pxelinux.0 $TFTP_ROOT/
    fi

    # Copy syslinux modules
    for f in ldlinux.c32 menu.c32 libutil.c32 libcom32.c32 vesamenu.c32; do
        find /usr/lib/syslinux -name "$f" -exec cp {} $TFTP_ROOT/ \; 2>/dev/null
    done

    # Copy kernel + initrd from current live system
    cp /live/vmlinuz $TFTP_ROOT/ 2>/dev/null || cp /boot/vmlinuz* $TFTP_ROOT/vmlinuz 2>/dev/null
    cp /live/initrd.img $TFTP_ROOT/ 2>/dev/null || cp /boot/initrd* $TFTP_ROOT/initrd.img 2>/dev/null

    # PXE boot config - auto install
    cat > $TFTP_ROOT/pxelinux.cfg/default << EOF
DEFAULT install
TIMEOUT 30
PROMPT 0

LABEL install
  MENU LABEL ChumChim Auto Install
  kernel vmlinuz
  append initrd=initrd.img boot=live components quiet fetch=http://${NET_IP}:8080/filesystem.squashfs ocs_live_run="/usr/local/bin/auto-restore" ocs_live_batch="yes" ocs_prerun="mount -t nfs ${NET_IP}:/home/partimag /home/partimag"
EOF

    # UEFI PXE boot
    mkdir -p $TFTP_ROOT/grub
    cp /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed $TFTP_ROOT/grubx64.efi 2>/dev/null
    cat > $TFTP_ROOT/grub/grub.cfg << EOF
set default=0
set timeout=3
menuentry "ChumChim Auto Install" {
  linux vmlinuz boot=live components quiet fetch=http://${NET_IP}:8080/filesystem.squashfs ocs_live_run="/usr/local/bin/auto-restore" ocs_live_batch="yes" ocs_prerun="mount -t nfs ${NET_IP}:/home/partimag /home/partimag"
  initrd initrd.img
}
EOF

    # Start dnsmasq as ProxyDHCP + TFTP
    killall dnsmasq 2>/dev/null

    cat > /tmp/dnsmasq.conf << EOF
# ProxyDHCP - don't conflict with existing DHCP
port=0
dhcp-range=${NET_SUBNET},proxy
dhcp-boot=pxelinux.0
pxe-service=x86PC,"ChumChim Install",pxelinux
pxe-service=X86-64_EFI,"ChumChim Install",grubx64.efi

# TFTP
enable-tftp
tftp-root=${TFTP_ROOT}

# Logging
log-dhcp
log-facility=/tmp/dnsmasq.log

interface=${NET_IF}
EOF

    dnsmasq -C /tmp/dnsmasq.conf
    echo "  [OK] PXE server started"
}

# ============================================
# Setup NFS + HTTP for image
# ============================================

setup_image_server() {
    # NFS share
    echo "  Starting NFS server..."
    echo "/home/partimag *(ro,sync,no_subtree_check,no_root_squash)" > /etc/exports
    exportfs -ra 2>/dev/null
    service nfs-kernel-server start 2>/dev/null || rpc.nfsd 2>/dev/null

    # HTTP server for filesystem.squashfs
    echo "  Starting HTTP server..."
    cd /live
    python3 -m http.server 8080 --bind $NET_IP &
    HTTP_PID=$!

    echo "  [OK] Image server started"
}

# ============================================
# Auto-restore script (runs on each client)
# ============================================

create_auto_restore() {
    cat > /usr/local/bin/auto-restore << 'RESTORE_EOF'
#!/bin/bash
# Auto-restore on PXE-booted client
sleep 5

# Find target disk (largest non-USB disk)
TGT=""
MAX_SIZE=0
for disk in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
    # Skip USB
    TRANSPORT=$(cat /sys/block/$disk/device/transport 2>/dev/null)
    if [ "$TRANSPORT" = "usb" ]; then continue; fi
    SIZE=$(lsblk -b -d -o SIZE /dev/$disk | tail -1)
    if [ "$SIZE" -gt "$MAX_SIZE" ] 2>/dev/null; then
        MAX_SIZE=$SIZE
        TGT=$disk
    fi
done

if [ -z "$TGT" ]; then
    echo "No target disk found!"
    sleep 999
    exit 1
fi

# Find image name
IMG_NAME=$(ls /home/partimag/ | head -1)
if [ -z "$IMG_NAME" ]; then
    echo "No image found!"
    sleep 999
    exit 1
fi

echo "Auto-installing: $IMG_NAME -> /dev/$TGT"

# Run Clonezilla restore
ocs-sr -g auto -e1 auto -e2 -r -j2 -c -batch -p poweroff restoredisk "$IMG_NAME" "$TGT"
RESTORE_EOF
    chmod +x /usr/local/bin/auto-restore
}

# ============================================
# Monitor dashboard
# ============================================

show_dashboard() {
    IMG_NAME=$1
    TOTAL=$2

    while true; do
        clear
        echo ""
        echo "  ============================================"
        echo "    ChumChim Multicast Server"
        echo "    Image: $IMG_NAME"
        echo "  ============================================"
        echo ""

        # Count connected clients from dnsmasq log
        if [ -f /tmp/dnsmasq.log ]; then
            CONNECTED=$(grep -c "DHCPREQUEST\|DHCPACK" /tmp/dnsmasq.log 2>/dev/null | head -1)
            CLIENTS=$(grep "DHCPACK" /tmp/dnsmasq.log 2>/dev/null | awk '{print $NF}' | sort -u)
        else
            CONNECTED=0
            CLIENTS=""
        fi

        DONE=0
        echo "  Connected PCs:"
        echo "  -----------------------------------------------"

        if [ -n "$CLIENTS" ]; then
            for client in $CLIENTS; do
                # Try to check if client is done (ping check)
                STATUS="installing..."
                ping -c 1 -W 1 $client > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                    STATUS="done (offline)"
                    DONE=$((DONE + 1))
                fi
                echo "    $client  [$STATUS]"
            done
        else
            echo "    Waiting for PCs to connect..."
            echo "    Tell them to press F12 > Network Boot"
        fi

        echo "  -----------------------------------------------"
        echo ""
        echo "  Status: $CONNECTED connected / $DONE completed"
        echo ""
        echo "  Server IP: $NET_IP"
        echo "  Time: $(date '+%H:%M:%S')"
        echo ""
        echo "  [Q] Stop server and go back"

        # Check for quit
        read -t 5 -n 1 key 2>/dev/null
        if [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            return
        fi
    done
}

# ============================================
# Main: Multicast Server
# ============================================

do_multicast() {
    clear
    echo ""
    echo "  ============================================"
    echo "    MULTICAST SERVER"
    echo "    Deploy image to many PCs via LAN"
    echo "  ============================================"
    echo "" > $LOG_FILE

    # Step 1: Detect network
    echo "  [1/4] Detecting network..."
    detect_network
    if [ $? -ne 0 ]; then
        read -p "  Press Enter..."
        return
    fi
    echo ""

    # Step 2: Select image
    echo "  [2/4] Select image..."
    echo ""
    IMG_COUNT=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_mimg 2>/dev/null
        mount $dev /tmp/_mimg 2>/dev/null
        if [ -d "/tmp/_mimg" ]; then
            for dir in /tmp/_mimg/*/; do
                if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                    IMG_COUNT=$((IMG_COUNT + 1))
                    NAME=$(basename $dir)
                    SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    NOTE=""
                    [ -f "/tmp/_mimg/.note_${NAME}" ] && NOTE=" - $(cat /tmp/_mimg/.note_${NAME})"
                    echo "  [$IMG_COUNT] $NAME ($SIZE)$NOTE"
                    eval "MIMG_DEV_$IMG_COUNT=$dev"
                    eval "MIMG_NAME_$IMG_COUNT=$NAME"
                fi
            done
        fi
        umount /tmp/_mimg 2>/dev/null
    done

    if [ $IMG_COUNT -eq 0 ]; then
        echo "  No images found!"
        read -p "  Press Enter..."; return
    fi

    echo ""
    read -p "  Select image: " MSEL
    eval "MIMG_DEV=\$MIMG_DEV_$MSEL"
    eval "MIMG_NAME=\$MIMG_NAME_$MSEL"

    if [ -z "$MIMG_NAME" ]; then
        echo "  Cancelled."
        read -p "  Press Enter..."; return
    fi

    # Mount image
    mkdir -p /home/partimag
    mount $MIMG_DEV /home/partimag 2>/dev/null

    echo ""
    read -p "  How many PCs to deploy? " TOTAL_PCS
    [ -z "$TOTAL_PCS" ] && TOTAL_PCS=30

    # Step 3: Start servers
    echo ""
    echo "  [3/4] Starting servers..."
    setup_pxe_server
    setup_image_server
    create_auto_restore

    # Step 4: Dashboard
    echo ""
    echo "  [4/4] Server running!"
    echo ""
    echo "  ============================================"
    echo "    Server is ready!"
    echo "    IP: $NET_IP"
    echo ""
    echo "    Now go to each PC and:"
    echo "    1. Turn on"
    echo "    2. Press F12"
    echo "    3. Select Network Boot"
    echo "    4. Image will install automatically!"
    echo "  ============================================"
    echo ""
    read -p "  Press Enter to open dashboard..."

    show_dashboard "$MIMG_NAME" "$TOTAL_PCS"

    # Cleanup
    echo "  Stopping servers..."
    killall dnsmasq 2>/dev/null
    kill $HTTP_PID 2>/dev/null
    killall python3 2>/dev/null
    service nfs-kernel-server stop 2>/dev/null
    umount /home/partimag 2>/dev/null
    echo "  [OK] Servers stopped"
    read -p "  Press Enter..."
}
