#!/bin/bash
# ============================================
#   ChumChim LAN Server — Simple & Reliable
#   NFS server for Clone/Install via LAN
# ============================================

LAN_LOG="/tmp/chumchim-lan.log"
LAN_PORT=19750
LAN_MAGIC="CHUMCHIM_NFS"
LAN_NFS_PATH="/srv/chumchim"
LAN_IF=""
LAN_IP=""
LAN_SERVER_IP=""
LAN_DISK=""
PXE_TFTP_ROOT="/srv/tftp"
PXE_NFS_LIVE="/srv/chumchim-live"

lan_log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LAN_LOG"; }

# ============================================
# Get network IP (DHCP or static fallback)
# ============================================
lan_get_ip() {
    local role="${1:-client}"
    LAN_IF=""; LAN_IP=""

    # Check existing IP
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ip link set "$iface" up 2>/dev/null
        local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
            LAN_IF="$iface"; LAN_IP="$ip"
            lan_log "Found IP: $ip on $iface"
            return 0
        fi
    done

    # Try DHCP
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ip link set "$iface" up 2>/dev/null
        dhclient -timeout 5 "$iface" 2>/dev/null
        local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
            LAN_IF="$iface"; LAN_IP="$ip"
            lan_log "DHCP IP: $ip on $iface"
            return 0
        fi
    done

    # Static fallback
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ip link set "$iface" up 2>/dev/null
        if [ "$role" = "server" ]; then
            ip addr add 192.168.77.1/24 broadcast 192.168.77.255 dev "$iface" 2>/dev/null
            LAN_IF="$iface"; LAN_IP="192.168.77.1"
        else
            local octet=$((RANDOM % 200 + 10))
            ip addr add 192.168.77.${octet}/24 broadcast 192.168.77.255 dev "$iface" 2>/dev/null
            LAN_IF="$iface"; LAN_IP="192.168.77.${octet}"
        fi
        lan_log "Static IP: $LAN_IP on $iface ($role)"
        return 0
    done
    return 1
}

# ============================================
# Discover LAN server (UDP listen)
# ============================================
lan_discover_server() {
    LAN_SERVER_IP=""
    local timeout="${1:-5}"
    local response=""

    # Try socat
    if command -v socat >/dev/null 2>&1; then
        response=$(timeout "$timeout" socat -T "$timeout" UDP-RECVFROM:${LAN_PORT},reuseaddr STDOUT 2>/dev/null | head -1)
    fi

    # Fallback to nc
    if [ -z "$response" ] && command -v nc >/dev/null 2>&1; then
        response=$(timeout "$timeout" nc -u -l -p ${LAN_PORT} 2>/dev/null | head -1)
    fi

    if echo "$response" | grep -q "^${LAN_MAGIC}|"; then
        LAN_SERVER_IP=$(echo "$response" | cut -d'|' -f2 | tr -d '[:space:]')
        [ -n "$LAN_SERVER_IP" ] && { lan_log "Found server: $LAN_SERVER_IP"; return 0; }
    fi

    lan_log "No server found (${timeout}s)"
    return 1
}

# ============================================
# CLIENT: Try NFS for clone (auto-detect)
# ============================================
lan_try_nfs_for_clone() {
    # Get network first
    [ -z "$LAN_IP" ] && lan_get_ip client
    [ -z "$LAN_IP" ] && return 1

    # Discover server
    lan_discover_server 3 || return 1

    # Mount NFS
    mkdir -p /home/partimag
    mount -t nfs -o rsize=65536,wsize=65536,nolock,vers=3 \
        "${LAN_SERVER_IP}:${LAN_NFS_PATH}" /home/partimag 2>/dev/null
    if [ $? -ne 0 ]; then
        mount -t nfs "${LAN_SERVER_IP}:${LAN_NFS_PATH}" /home/partimag 2>/dev/null
    fi
    [ $? -ne 0 ] && { lan_log "NFS mount failed"; return 1; }

    # Write test
    touch /home/partimag/.writetest 2>/dev/null || { umount /home/partimag 2>/dev/null; return 1; }
    rm -f /home/partimag/.writetest

    lan_log "NFS ready for clone at $LAN_SERVER_IP"
    return 0
}

# ============================================
# CLIENT: Try NFS for install (auto-detect)
# ============================================
lan_try_nfs_for_install() {
    [ -z "$LAN_IP" ] && lan_get_ip client
    [ -z "$LAN_IP" ] && return 1

    lan_discover_server 10 || return 1

    mkdir -p /home/partimag
    mount -t nfs -o rsize=65536,wsize=65536,nolock,vers=3 \
        "${LAN_SERVER_IP}:${LAN_NFS_PATH}" /home/partimag 2>/dev/null
    if [ $? -ne 0 ]; then
        mount -t nfs "${LAN_SERVER_IP}:${LAN_NFS_PATH}" /home/partimag 2>/dev/null
    fi
    [ $? -ne 0 ] && { lan_log "NFS mount failed"; return 1; }

    # Check if any images exist
    local count=0
    for dir in /home/partimag/*/; do
        [ -f "${dir}disk" ] 2>/dev/null && count=$((count + 1))
    done
    [ $count -eq 0 ] && { umount /home/partimag 2>/dev/null; return 1; }

    lan_log "NFS ready for install at $LAN_SERVER_IP ($count images)"
    return 0
}

# ============================================
# CLIENT: Select image from NFS mount
# ============================================
lan_select_nfs_image() {
    SEL_IMG_NAME=""
    local -a NAMES=()
    local OPTS="" COUNT=0
    for dir in /home/partimag/*/; do
        if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
            COUNT=$((COUNT + 1))
            local name=$(basename "$dir")
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            OPTS="$OPTS $COUNT \"$name ($size)\""
            NAMES[$COUNT]="$name"
        fi
    done
    [ $COUNT -eq 0 ] && return 1
    # Auto-select if only 1 image
    if [ $COUNT -eq 1 ]; then
        SEL_IMG_NAME="${NAMES[1]}"
        return 0
    fi
    local RESULT=$(eval "dialog --title 'Select Image' --menu '' 15 60 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    SEL_IMG_NAME="${NAMES[$RESULT]}"
    return 0
}

# ============================================
# SERVER: Setup PXE boot (BIOS + UEFI)
# ============================================
pxe_setup_tftp() {
    lan_log "Setting up TFTP boot files..."
    mkdir -p "$PXE_TFTP_ROOT/bios" "$PXE_TFTP_ROOT/efi64"

    # --- BIOS: pxelinux ---
    local pxelinux_path=""
    for p in /usr/lib/PXELINUX/pxelinux.0 /usr/share/syslinux/pxelinux.0; do
        [ -f "$p" ] && { pxelinux_path="$p"; break; }
    done
    if [ -n "$pxelinux_path" ]; then
        cp "$pxelinux_path" "$PXE_TFTP_ROOT/bios/"
        # Copy required syslinux modules
        for mod in ldlinux.c32 menu.c32 vesamenu.c32 libutil.c32 libcom32.c32; do
            for d in /usr/lib/syslinux/modules/bios /usr/share/syslinux; do
                [ -f "$d/$mod" ] && { cp "$d/$mod" "$PXE_TFTP_ROOT/bios/"; break; }
            done
        done
        lan_log "BIOS PXE files ready"
    else
        lan_log "WARNING: pxelinux.0 not found — BIOS PXE disabled"
    fi

    # --- UEFI: grub-efi ---
    local grub_efi=""
    for p in /usr/lib/grub/x86_64-efi /usr/share/grub/x86_64-efi; do
        [ -d "$p" ] && { grub_efi="$p"; break; }
    done
    if [ -n "$grub_efi" ]; then
        grub-mknetdir --net-directory="$PXE_TFTP_ROOT/efi64" --subdir="" 2>/dev/null || \
        grub-mkimage -O x86_64-efi -o "$PXE_TFTP_ROOT/efi64/bootx64.efi" \
            -p "(tftp)/" \
            efinet tftp linux normal configfile 2>/dev/null
        # Ensure bootx64.efi exists at all required paths
        if [ ! -f "$PXE_TFTP_ROOT/efi64/bootx64.efi" ]; then
            local core=""
            for f in "$PXE_TFTP_ROOT/efi64/boot/grub/x86_64-efi/core.efi" "$PXE_TFTP_ROOT/efi64/x86_64-efi/core.efi"; do
                [ -f "$f" ] && { core="$f"; break; }
            done
            [ -n "$core" ] && cp "$core" "$PXE_TFTP_ROOT/efi64/bootx64.efi"
        fi
        # Copy to TFTP root + EFI/BOOT (different firmware look in different places)
        cp "$PXE_TFTP_ROOT/efi64/bootx64.efi" "$PXE_TFTP_ROOT/bootx64.efi" 2>/dev/null
        mkdir -p "$PXE_TFTP_ROOT/EFI/BOOT"
        cp "$PXE_TFTP_ROOT/efi64/bootx64.efi" "$PXE_TFTP_ROOT/EFI/BOOT/bootx64.efi" 2>/dev/null
        lan_log "UEFI PXE files ready (bootx64.efi at root + EFI/BOOT)"
    else
        lan_log "WARNING: grub x86_64-efi modules not found — UEFI PXE disabled"
    fi

    # --- Copy kernel + initrd from running live system ---
    if [ -f /live/vmlinuz ] && [ -f /live/initrd.img ]; then
        cp /live/vmlinuz "$PXE_TFTP_ROOT/"
        cp /live/initrd.img "$PXE_TFTP_ROOT/"
    elif [ -f /boot/vmlinuz ] && [ -f /boot/initrd.img ]; then
        cp /boot/vmlinuz "$PXE_TFTP_ROOT/"
        cp /boot/initrd.img "$PXE_TFTP_ROOT/"
    else
        # Try to extract from ISO mount
        for mnt in /run/live/medium /lib/live/mount/medium /cdrom; do
            if [ -f "$mnt/live/vmlinuz" ]; then
                cp "$mnt/live/vmlinuz" "$PXE_TFTP_ROOT/"
                cp "$mnt/live/initrd.img" "$PXE_TFTP_ROOT/"
                break
            fi
        done
    fi

    if [ ! -f "$PXE_TFTP_ROOT/vmlinuz" ]; then
        lan_log "ERROR: vmlinuz not found for PXE"
        return 1
    fi

    # --- BIOS pxelinux config ---
    mkdir -p "$PXE_TFTP_ROOT/bios/pxelinux.cfg"
    cat > "$PXE_TFTP_ROOT/bios/pxelinux.cfg/default" << PXECFG
DEFAULT chumchim
PROMPT 0
TIMEOUT 30
LABEL chumchim
  MENU LABEL ChumChim-Clonezilla (PXE)
  KERNEL vmlinuz
  APPEND initrd=initrd.img boot=live netboot=nfs nfsroot=${LAN_IP}:${PXE_NFS_LIVE} union=overlay username=user locales=en_US.UTF-8 keyboard-layouts=us chumchim_server=${LAN_IP} chumchim_pxe=1
PXECFG

    # --- UEFI grub config ---
    cat > "$PXE_TFTP_ROOT/efi64/grub.cfg" << GRUBCFG
set default=0
set timeout=3
menuentry "ChumChim-Clonezilla (PXE)" {
  linux /vmlinuz boot=live netboot=nfs nfsroot=${LAN_IP}:${PXE_NFS_LIVE} union=overlay username=user locales=en_US.UTF-8 keyboard-layouts=us chumchim_server=${LAN_IP} chumchim_pxe=1
  initrd /initrd.img
}
GRUBCFG

    # Copy grub.cfg to all locations GRUB may look for
    cp "$PXE_TFTP_ROOT/efi64/grub.cfg" "$PXE_TFTP_ROOT/grub.cfg" 2>/dev/null
    cp "$PXE_TFTP_ROOT/efi64/grub.cfg" "$PXE_TFTP_ROOT/boot/grub/grub.cfg" 2>/dev/null
    mkdir -p "$PXE_TFTP_ROOT/EFI/BOOT"
    cp "$PXE_TFTP_ROOT/efi64/grub.cfg" "$PXE_TFTP_ROOT/EFI/BOOT/grub.cfg" 2>/dev/null

    lan_log "TFTP boot configs written (server=$LAN_IP)"
    return 0
}

# ============================================
# SERVER: Export live filesystem via NFS
# ============================================
pxe_export_live_nfs() {
    lan_log "Exporting live filesystem for PXE clients..."
    mkdir -p "$PXE_NFS_LIVE"

    # Find the squashfs / live mount
    local live_root=""
    for mnt in /run/live/rootfs /lib/live/mount/rootfs; do
        if [ -d "$mnt" ] && ls "$mnt"/*.squashfs >/dev/null 2>&1; then
            live_root="$mnt"
            break
        fi
    done

    if [ -z "$live_root" ]; then
        # Fallback: mount the squashfs from ISO medium
        local medium=""
        for m in /run/live/medium /lib/live/mount/medium /cdrom; do
            [ -f "$m/live/filesystem.squashfs" ] && { medium="$m"; break; }
        done
        if [ -n "$medium" ]; then
            # Create a read-only bind of the entire live medium
            mount --bind "$medium" "$PXE_NFS_LIVE" 2>/dev/null
            lan_log "Bound live medium $medium -> $PXE_NFS_LIVE"
        else
            lan_log "ERROR: Cannot find live filesystem for PXE export"
            return 1
        fi
    else
        # Bind the rootfs directory (contains squashfs files)
        mount --bind "$live_root" "$PXE_NFS_LIVE" 2>/dev/null
        lan_log "Bound live rootfs $live_root -> $PXE_NFS_LIVE"
    fi

    # Also try binding the full medium for live boot
    local medium=""
    for m in /run/live/medium /lib/live/mount/medium /cdrom; do
        [ -d "$m/live" ] && { medium="$m"; break; }
    done
    if [ -n "$medium" ]; then
        umount "$PXE_NFS_LIVE" 2>/dev/null
        mount --bind "$medium" "$PXE_NFS_LIVE" 2>/dev/null
        lan_log "Bound full medium $medium -> $PXE_NFS_LIVE"
    fi

    return 0
}

# ============================================
# SERVER: Start dnsmasq as ProxyDHCP + TFTP
# ============================================
pxe_start_dnsmasq() {
    lan_log "Starting dnsmasq (ProxyDHCP + TFTP)..."

    # Kill any existing dnsmasq
    killall dnsmasq 2>/dev/null
    sleep 1

    # Detect UEFI boot file
    local uefi_file=""
    if [ -f "$PXE_TFTP_ROOT/efi64/bootx64.efi" ]; then
        uefi_file="efi64/bootx64.efi"
    elif [ -f "$PXE_TFTP_ROOT/efi64/boot/grub/x86_64-efi/core.efi" ]; then
        uefi_file="efi64/boot/grub/x86_64-efi/core.efi"
    fi

    # Detect if DHCP exists on network
    local has_dhcp=0
    timeout 3 dhclient -1 -timeout 3 "$LAN_IF" 2>/dev/null && has_dhcp=1
    # Release immediately if we got one
    dhclient -r "$LAN_IF" 2>/dev/null
    # Re-assign our static IP
    ip addr add ${LAN_IP}/24 broadcast 192.168.77.255 dev "$LAN_IF" 2>/dev/null

    # Calculate DHCP range (server IP is .X, clients get .100-.200)
    local subnet=$(echo $LAN_IP | cut -d. -f1-3)

    if [ "$has_dhcp" = "1" ]; then
        lan_log "Existing DHCP detected — using ProxyDHCP mode"
        cat > /tmp/dnsmasq-pxe.conf << DNSMASQCFG
# ProxyDHCP mode (existing DHCP on network)
port=0
interface=${LAN_IF}
bind-interfaces
dhcp-range=${LAN_IP},proxy
dhcp-no-override
dhcp-option=66,${LAN_IP}
DNSMASQCFG
    else
        lan_log "No DHCP detected — running full DHCP + PXE"
        cat > /tmp/dnsmasq-pxe.conf << DNSMASQCFG
# Full DHCP mode (no existing DHCP)
interface=${LAN_IF}
bind-interfaces
dhcp-range=${subnet}.100,${subnet}.200,255.255.255.0,1h
dhcp-option=option:router,${LAN_IP}
dhcp-option=66,${LAN_IP}
DNSMASQCFG
    fi

    # Append PXE boot options (same for both modes)
    cat >> /tmp/dnsmasq-pxe.conf << DNSMASQCFG

# BIOS clients (arch 0)
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,bios/pxelinux.0,,${LAN_IP}

# UEFI clients (arch 7,9)
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64-2,option:client-arch,9
dhcp-boot=tag:efi64,${uefi_file},,${LAN_IP}
dhcp-boot=tag:efi64-2,${uefi_file},,${LAN_IP}

# PXE service
pxe-service=x86PC,"ChumChim PXE",bios/pxelinux,${LAN_IP}
pxe-service=x86-64_EFI,"ChumChim PXE",${uefi_file},${LAN_IP}

# TFTP server
enable-tftp
tftp-root=${PXE_TFTP_ROOT}

# Logging
log-dhcp
log-facility=/tmp/dnsmasq-pxe.log
DNSMASQCFG

    dnsmasq --conf-file=/tmp/dnsmasq-pxe.conf 2>>/tmp/dnsmasq-pxe.log
    local rc=$?
    if [ $rc -eq 0 ]; then
        lan_log "dnsmasq started (ProxyDHCP on $LAN_IF, TFTP on $PXE_TFTP_ROOT)"
    else
        lan_log "ERROR: dnsmasq failed to start (rc=$rc)"
        return 1
    fi
    return 0
}

# ============================================
# SERVER: Main function
# ============================================
do_lan_server() {
    clear
    echo ""
    echo "  ============================================"
    echo "    ChumChim LAN Server Setup"
    echo "  ============================================"
    echo ""

    # Step 1: Network
    echo "  [1/5] Setting up network..."
    lan_get_ip server
    if [ -z "$LAN_IP" ]; then
        dialog --msgbox "No network!\n\nConnect LAN cable and try again." 8 45
        return
    fi
    echo "         IP: $LAN_IP ($LAN_IF)"

    # Step 2: Find disk
    echo "  [2/5] Finding storage disk..."
    LAN_DISK=""
    local max_size=0
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        local sz=$(blockdev --getsize64 "/dev/$dname" 2>/dev/null)
        [ -z "$sz" ] && continue
        if [ "$sz" -gt "$max_size" ]; then
            max_size=$sz
            LAN_DISK="$dname"
        fi
    done
    if [ -z "$LAN_DISK" ]; then
        dialog --msgbox "No disk found!" 6 30
        return
    fi
    local disk_gb=$((max_size / 1073741824))
    local disk_model=$(lsblk -d -o MODEL "/dev/$LAN_DISK" 2>/dev/null | tail -1)
    echo "         Disk: /dev/$LAN_DISK ($disk_gb GB) $disk_model"

    # Step 3: Prepare storage
    echo "  [3/5] Preparing storage..."
    mkdir -p "$LAN_NFS_PATH"
    # Enable FUSE allow_other for NFS+NTFS
    grep -q "user_allow_other" /etc/fuse.conf 2>/dev/null || echo "user_allow_other" >> /etc/fuse.conf

    # Find or create writable partition
    # Priority: ext4 > format biggest partition as ext4
    # NTFS via NFS is read-only, so we MUST use ext4
    local mounted=0

    # First: try existing ext4 partition
    for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
        local fs=$(blkid -o value -s TYPE "/dev/$pname" 2>/dev/null)
        if [ "$fs" = "ext4" ]; then
            mount "/dev/$pname" "$LAN_NFS_PATH" 2>/dev/null && { mounted=1; echo "         Mounted ext4 /dev/$pname"; break; }
        fi
    done

    # Second: try NTFS with ntfs-3g (read-write)
    if [ "$mounted" = "0" ]; then
        for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
            local fs=$(blkid -o value -s TYPE "/dev/$pname" 2>/dev/null)
            if [ "$fs" = "ntfs" ]; then
                # Try ntfs-3g for read-write NTFS
                ntfs-3g "/dev/$pname" "$LAN_NFS_PATH" -o rw,big_writes,allow_other 2>/dev/null && { mounted=1; echo "         Mounted NTFS /dev/$pname (ntfs-3g rw)"; break; }
                # Fallback: regular mount
                mount -t ntfs-3g "/dev/$pname" "$LAN_NFS_PATH" -o rw,big_writes,allow_other 2>/dev/null && { mounted=1; echo "         Mounted NTFS /dev/$pname (rw)"; break; }
            fi
        done
    fi

    # Third: format biggest partition as ext4
    if [ "$mounted" = "0" ]; then
        local part=""
        local biggest_size=0
        for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
            local psz=$(blockdev --getsize64 "/dev/$pname" 2>/dev/null)
            [ -z "$psz" ] && continue
            if [ "$psz" -gt "$biggest_size" ]; then
                biggest_size=$psz
                part="$pname"
            fi
        done
        if [ -z "$part" ]; then
            echo "         Creating partition..."
            echo -e "g\nn\n\n\n\nw" | fdisk "/dev/$LAN_DISK" >/dev/null 2>&1
            sleep 2
            partprobe "/dev/$LAN_DISK" 2>/dev/null
            sleep 1
            part=$(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$" | head -1)
        fi
        if [ -n "$part" ]; then
            echo "         Formatting /dev/$part as ext4..."
            mkfs.ext4 -F -L "ChumChim-LAN" "/dev/$part" >/dev/null 2>&1
            mount "/dev/$part" "$LAN_NFS_PATH" 2>/dev/null && mounted=1
        fi
    fi

    if [ "$mounted" = "0" ]; then
        dialog --msgbox "Cannot prepare storage!" 6 35
        return
    fi

    # Verify writable
    touch "$LAN_NFS_PATH/.writetest" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "         WARNING: Storage is READ-ONLY!"
        echo "         NTFS disks need ntfs-3g for write access."
        echo "         Trying to remount with ntfs-3g..."
        umount "$LAN_NFS_PATH" 2>/dev/null
        # Find the mounted partition and try ntfs-3g
        for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
            ntfs-3g "/dev/$pname" "$LAN_NFS_PATH" -o rw,big_writes,allow_other 2>/dev/null && break
        done
        touch "$LAN_NFS_PATH/.writetest" 2>/dev/null
        if [ $? -ne 0 ]; then
            dialog --msgbox "Storage is READ-ONLY!\n\nCannot write to disk.\nNeed ext4 formatted disk." 10 50
            return
        fi
    fi
    rm -f "$LAN_NFS_PATH/.writetest"

    local free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')
    echo "         Storage: $free free"

    # Step 4: Start NFS + beacon
    echo "  [4/5] Starting NFS server..."
    echo "$LAN_NFS_PATH *(rw,sync,no_subtree_check,no_root_squash,insecure,fsid=1)" > /etc/exports
    rpcbind 2>/dev/null
    rpc.nfsd 8 2>/dev/null
    rpc.mountd 2>/dev/null
    exportfs -ra 2>/dev/null
    echo "         NFS: OK"

    # Start beacon
    local bcast=$(ip -4 addr show "$LAN_IF" 2>/dev/null | grep "brd " | awk '{print $4}' | head -1)
    [ -z "$bcast" ] && bcast="192.168.77.255"
    (
        while true; do
            echo "${LAN_MAGIC}|${LAN_IP}" | socat - UDP-DATAGRAM:${bcast}:${LAN_PORT},broadcast,so-broadcast 2>/dev/null || true
            sleep 2
        done
    ) &
    echo "         Beacon: broadcasting on $bcast:$LAN_PORT"

    # Step 5: PXE Boot Server
    echo "  [5/5] Starting PXE Boot Server..."
    local pxe_status="OFF"
    if command -v dnsmasq >/dev/null 2>&1; then
        # Export live filesystem for PXE clients
        pxe_export_live_nfs
        # Add NFS export for live filesystem
        echo "$PXE_NFS_LIVE *(ro,sync,no_subtree_check,no_root_squash,insecure,fsid=2)" >> /etc/exports
        exportfs -ra 2>/dev/null

        # Setup TFTP boot files
        pxe_setup_tftp
        # Start dnsmasq ProxyDHCP + TFTP
        if pxe_start_dnsmasq; then
            pxe_status="ON"
            echo "         PXE: BIOS + UEFI ready"
        else
            echo "         PXE: FAILED (see /tmp/dnsmasq-pxe.log)"
        fi
    else
        echo "         PXE: skipped (dnsmasq not installed)"
    fi

    # Dashboard loop — refresh every 10 seconds
    while true; do
        clear
        local free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')
        local used=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $3}')
        local clients=$(cat /var/lib/nfs/rmtab 2>/dev/null | wc -l)

        local pxe_clients=0
        [ -f /tmp/dnsmasq-pxe.log ] && pxe_clients=$(grep -c "DHCPACK" /tmp/dnsmasq-pxe.log 2>/dev/null)

        echo ""
        echo "  ╔══════════════════════════════════════════╗"
        echo "  ║       ChumChim LAN Server  [READY]       ║"
        echo "  ╚══════════════════════════════════════════╝"
        echo ""
        echo "  Server IP:    $LAN_IP"
        echo "  Disk:         /dev/$LAN_DISK ($disk_gb GB) $disk_model"
        echo "  Storage:      $used used / $free free"
        echo "  NFS Clients:  $clients PC(s)"
        echo "  PXE Boot:     $pxe_status (BIOS+UEFI) | $pxe_clients boot(s)"
        echo ""
        echo "  USB PCs:  select Clone or Install (auto-find server)"
        echo "  PXE PCs:  set BIOS to 'Network Boot' -> auto-install"
        echo ""

        # Image table
        echo "  ┌──────────────────────────────────────────┐"
        echo "  │  IMAGES                                  │"
        echo "  ├──────────────────────────────────────────┤"
        local img_count=0
        for dir in $LAN_NFS_PATH/*/; do
            [ -f "${dir}disk" ] 2>/dev/null || continue
            img_count=$((img_count + 1))
            local name=$(basename "$dir")
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local date=$(stat -c %Y "$dir" 2>/dev/null)
            local date_fmt=$(date -d "@$date" '+%Y-%m-%d %H:%M' 2>/dev/null)
            local note=""
            [ -f "$LAN_NFS_PATH/.note_${name}" ] && note=$(cat "$LAN_NFS_PATH/.note_${name}" 2>/dev/null)
            printf "  │  %-20s %6s  %s\n" "$name" "$size" "$date_fmt"
            [ -n "$note" ] && printf "  │    Note: %s\n" "$note"
        done
        if [ $img_count -eq 0 ]; then
            echo "  │  (no images yet — waiting for Clone)   │"
        fi
        echo "  └──────────────────────────────────────────┘"

        # Client status
        echo ""
        echo "  ┌──────────────────────────────────────────────────┐"
        echo "  │  PC STATUS                                       │"
        echo "  ├──────────────────────────────────────────────────┤"
        printf "  │  %-8s %-16s %-8s %-7s %-10s │\n" "TIME" "IP" "ACTION" "STATUS" "IMAGE"
        echo "  ├──────────────────────────────────────────────────┤"
        local has_status=0
        if [ -f "$LAN_NFS_PATH/.client_status" ]; then
            while IFS='|' read -r time ip action status image extra; do
                [ -z "$time" ] && continue
                has_status=1
                local icon="..."
                [ "$status" = "OK" ] && icon="[OK]"
                [ "$status" = "FAILED" ] && icon="[X]"
                printf "  │  %-8s %-16s %-8s %-7s %-10s │\n" "$time" "$ip" "$action" "$icon" "$image"
            done < "$LAN_NFS_PATH/.client_status"
        fi
        # Show currently connected (active)
        if [ -f /var/lib/nfs/rmtab ]; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local cip=$(echo "$line" | cut -d: -f1)
                # Check if already in status file
                if ! grep -q "$cip" "$LAN_NFS_PATH/.client_status" 2>/dev/null; then
                    has_status=1
                    printf "  │  %-8s %-16s %-8s %-7s %-10s │\n" "$(date '+%H:%M')" "$cip" "..." "[...]" "working"
                fi
            done < /var/lib/nfs/rmtab
        fi
        if [ $has_status -eq 0 ]; then
            echo "  │  (waiting for PCs to connect...)                │"
        fi
        echo "  └──────────────────────────────────────────────────┘"
        echo ""
        echo "  Last update: $(date '+%H:%M:%S')  |  Refresh: 10s"
        echo "  Press Ctrl+C to stop server."

        sleep 10
    done
}
