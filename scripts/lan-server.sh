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
    echo "  [1/4] Setting up network..."
    lan_get_ip server
    if [ -z "$LAN_IP" ]; then
        dialog --msgbox "No network!\n\nConnect LAN cable and try again." 8 45
        return
    fi
    echo "         IP: $LAN_IP ($LAN_IF)"

    # Step 2: Find disk
    echo "  [2/4] Finding storage disk..."
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
    echo "  [3/4] Preparing storage..."
    mkdir -p "$LAN_NFS_PATH"

    # Find or create ext4 partition
    local mounted=0
    for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
        local fs=$(blkid -o value -s TYPE "/dev/$pname" 2>/dev/null)
        if [ "$fs" = "ext4" ] || [ "$fs" = "ntfs" ]; then
            mount "/dev/$pname" "$LAN_NFS_PATH" 2>/dev/null && { mounted=1; echo "         Mounted /dev/$pname"; break; }
        fi
    done

    if [ "$mounted" = "0" ]; then
        # Need to format — find biggest partition or create one
        local part=""
        for pname in $(lsblk -l -o NAME "/dev/$LAN_DISK" 2>/dev/null | tail -n +2 | grep -v "^${LAN_DISK}$"); do
            part="$pname"; break
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

    local free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')
    echo "         Storage: $free free"

    # Step 4: Start NFS + beacon
    echo "  [4/4] Starting NFS server..."
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

    # Dashboard loop — refresh every 10 seconds
    while true; do
        clear
        local free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')
        local used=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $3}')
        local clients=$(cat /var/lib/nfs/rmtab 2>/dev/null | wc -l)

        echo ""
        echo "  ╔══════════════════════════════════════════╗"
        echo "  ║       ChumChim LAN Server  [READY]       ║"
        echo "  ╚══════════════════════════════════════════╝"
        echo ""
        echo "  Server IP:    $LAN_IP"
        echo "  Disk:         /dev/$LAN_DISK ($disk_gb GB) $disk_model"
        echo "  Storage:      $used used / $free free"
        echo "  Connected:    $clients PC(s)"
        echo ""
        echo "  Other PCs: just select Clone or Install"
        echo "  They will find this server automatically."
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
