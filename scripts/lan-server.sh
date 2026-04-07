#!/bin/bash
# ============================================
#   ChumChim LAN Clone Server + Client
#   PC-B: NFS server on largest internal HDD
#   PC-A: Clone to NFS (auto-detect)
#   PC-C,D,E: Install from NFS (auto-detect)
# ============================================

LAN_LOG="/tmp/chumchim-lan.log"
LAN_PORT=19750
LAN_MAGIC="CHUMCHIM_NFS"
LAN_NFS_PATH="/srv/chumchim"
LAN_BEACON_PID=""
LAN_LISTENER_PID=""

lan_log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LAN_LOG"
}

# ============================================
# Network: bring up all interfaces via DHCP
# ============================================
lan_get_ip() {
    LAN_IF=""
    LAN_IP=""

    # Check if any interface already has an IP
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        local ip
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$ip" ]; then
            LAN_IF="$iface"
            LAN_IP="$ip"
            lan_log "Interface $iface already has IP: $ip"
            return 0
        fi
    done

    # Try DHCP on each interface
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ip link set "$iface" up 2>/dev/null
        dhclient -timeout 8 "$iface" 2>/dev/null
        local ip
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$ip" ]; then
            LAN_IF="$iface"
            LAN_IP="$ip"
            lan_log "Got DHCP IP on $iface: $ip"
            return 0
        fi
    done

    # No DHCP — assign static fallback
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ip link set "$iface" up 2>/dev/null
        ip addr add 192.168.77.1/24 dev "$iface" 2>/dev/null
        LAN_IF="$iface"
        LAN_IP="192.168.77.1"
        lan_log "No DHCP, assigned static $LAN_IP on $iface"
        return 0
    done

    return 1
}

# ============================================
# Detect largest internal (non-USB) disk
# ============================================
lan_detect_largest_disk() {
    LAN_DISK=""
    LAN_DISK_DEV=""
    local max_bytes=0

    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        # Skip boot USB
        [ "/dev/$dname" = "$BOOT_USB" ] && continue
        # Skip removable
        local rm_flag
        rm_flag=$(lsblk -d -o RM "/dev/$dname" 2>/dev/null | tail -1 | tr -d ' ')
        [ "$rm_flag" = "1" ] && continue
        local sz
        sz=$(blockdev --getsize64 "/dev/$dname" 2>/dev/null)
        [ -z "$sz" ] && continue
        if [ "$sz" -gt "$max_bytes" ] 2>/dev/null; then
            max_bytes=$sz
            LAN_DISK="$dname"
            LAN_DISK_DEV="/dev/$dname"
        fi
    done

    [ -z "$LAN_DISK" ] && return 1
    return 0
}

# ============================================
# Prepare storage: find or create ext4
#   partition on the largest disk
# ============================================
lan_prepare_storage() {
    local disk="$1"
    local mount_point="$2"

    mkdir -p "$mount_point"

    # First: look for an existing ext4 partition with enough space
    for pname in $(lsblk -l -o NAME "/dev/$disk" 2>/dev/null | tail -n +2 | grep -v "^${disk}$"); do
        local fs
        fs=$(blkid -o value -s TYPE "/dev/$pname" 2>/dev/null)
        if [ "$fs" = "ext4" ]; then
            mount "/dev/$pname" "$mount_point" 2>/dev/null
            if [ $? -eq 0 ]; then
                local free_mb
                free_mb=$(df -m "$mount_point" 2>/dev/null | tail -1 | awk '{print $4}')
                [ -z "$free_mb" ] && free_mb=0
                if [ "$free_mb" -gt 5000 ]; then
                    lan_log "Using existing ext4: /dev/$pname (${free_mb}MB free)"
                    return 0
                fi
                umount "$mount_point" 2>/dev/null
            fi
        fi
    done

    # No suitable partition — find the largest partition and format it
    local biggest_part=""
    local biggest_size=0
    for pname in $(lsblk -l -o NAME "/dev/$disk" 2>/dev/null | tail -n +2 | grep -v "^${disk}$"); do
        local psz
        psz=$(blockdev --getsize64 "/dev/$pname" 2>/dev/null)
        [ -z "$psz" ] && continue
        if [ "$psz" -gt "$biggest_size" ] 2>/dev/null; then
            biggest_size=$psz
            biggest_part="$pname"
        fi
    done

    # If no partitions exist, create one spanning the whole disk
    if [ -z "$biggest_part" ]; then
        lan_log "No partitions on $disk, creating GPT + single partition..."
        parted -s "/dev/$disk" mklabel gpt 2>/dev/null
        parted -s "/dev/$disk" mkpart primary ext4 1MiB 100% 2>/dev/null
        partprobe "/dev/$disk" 2>/dev/null
        sleep 2

        # Find the new partition
        for pname in $(lsblk -l -o NAME "/dev/$disk" 2>/dev/null | tail -n +2 | grep -v "^${disk}$"); do
            biggest_part="$pname"
            break
        done
    fi

    [ -z "$biggest_part" ] && return 1

    local part_size_gb=$(( $(blockdev --getsize64 "/dev/$biggest_part" 2>/dev/null) / 1073741824 ))

    lan_log "Formatting /dev/$biggest_part (${part_size_gb}GB) as ext4..."
    mkfs.ext4 -F -L "ChumChim-LAN" "/dev/$biggest_part" 2>/dev/null
    if [ $? -ne 0 ]; then
        lan_log "mkfs.ext4 failed on /dev/$biggest_part"
        return 1
    fi

    mount "/dev/$biggest_part" "$mount_point" 2>/dev/null
    if [ $? -ne 0 ]; then
        lan_log "Cannot mount /dev/$biggest_part"
        return 1
    fi

    lan_log "Storage ready: /dev/$biggest_part mounted at $mount_point"
    return 0
}

# ============================================
# UDP beacon: broadcast server presence
# ============================================
lan_start_beacon() {
    local ip="$1"

    # Kill any existing beacon
    lan_stop_beacon

    # Broadcast every 2 seconds in background
    (
        while true; do
            echo "${LAN_MAGIC}|${ip}" | socat - UDP-DATAGRAM:255.255.255.255:${LAN_PORT},broadcast 2>/dev/null \
                || echo "${LAN_MAGIC}|${ip}" > /dev/udp/255.255.255.255/${LAN_PORT} 2>/dev/null \
                || true
            sleep 2
        done
    ) &
    LAN_BEACON_PID=$!
    lan_log "Beacon started (PID $LAN_BEACON_PID) broadcasting on port $LAN_PORT"
}

lan_stop_beacon() {
    [ -n "$LAN_BEACON_PID" ] && kill "$LAN_BEACON_PID" 2>/dev/null
    LAN_BEACON_PID=""
}

# ============================================
# UDP discover: listen for server beacon
# Returns 0 if found, sets LAN_SERVER_IP
# ============================================
lan_discover_server() {
    LAN_SERVER_IP=""
    local timeout="${1:-5}"

    # Try socat first (more reliable)
    local response
    response=$(timeout "$timeout" socat -T "$timeout" UDP-RECVFROM:${LAN_PORT},broadcast,reuseaddr STDOUT 2>/dev/null | head -1)

    if [ -z "$response" ]; then
        # Fallback: use bash /dev/udp if socat not available
        # This is less reliable for receiving broadcasts
        lan_log "socat not available or no response, trying nc..."
        response=$(timeout "$timeout" nc -u -l -p ${LAN_PORT} -w "$timeout" 2>/dev/null | head -1)
    fi

    if echo "$response" | grep -q "^${LAN_MAGIC}|"; then
        LAN_SERVER_IP=$(echo "$response" | cut -d'|' -f2 | tr -d '[:space:]')
        if [ -n "$LAN_SERVER_IP" ]; then
            lan_log "Discovered server at $LAN_SERVER_IP"
            return 0
        fi
    fi

    lan_log "No LAN server found (waited ${timeout}s)"
    return 1
}

# ============================================
# NFS server: export /srv/chumchim
# ============================================
lan_start_nfs_server() {
    local export_path="$1"

    # Configure exports
    echo "${export_path} *(rw,sync,no_subtree_check,no_root_squash,insecure)" > /etc/exports

    # Start NFS services
    rpcbind 2>/dev/null || true
    rpc.statd 2>/dev/null || true
    exportfs -ra 2>/dev/null

    # Try systemd first, then direct daemon start
    service nfs-kernel-server start 2>/dev/null \
        || systemctl start nfs-server 2>/dev/null \
        || rpc.nfsd 8 2>/dev/null

    rpc.mountd 2>/dev/null || true

    # Verify
    if exportfs -v 2>/dev/null | grep -q "$export_path"; then
        lan_log "NFS server exporting $export_path"
        return 0
    else
        lan_log "NFS export verification failed, but may still work"
        return 0
    fi
}

lan_stop_nfs_server() {
    exportfs -ua 2>/dev/null
    service nfs-kernel-server stop 2>/dev/null \
        || systemctl stop nfs-server 2>/dev/null
    killall rpc.nfsd rpc.mountd 2>/dev/null
    lan_log "NFS server stopped"
}

# ============================================
# NFS client: mount remote NFS share
# ============================================
lan_mount_nfs() {
    local server_ip="$1"
    local remote_path="$2"
    local local_mount="$3"

    mkdir -p "$local_mount"

    # Start NFS client services
    rpcbind 2>/dev/null || true
    rpc.statd 2>/dev/null || true

    # Mount with NFS v3 (simpler, works without full v4 setup)
    mount -t nfs -o vers=3,nolock,tcp,rsize=1048576,wsize=1048576 \
        "${server_ip}:${remote_path}" "$local_mount" 2>/dev/null
    if [ $? -eq 0 ]; then
        lan_log "NFS mounted: ${server_ip}:${remote_path} -> $local_mount"
        return 0
    fi

    # Fallback: try v4
    mount -t nfs "${server_ip}:${remote_path}" "$local_mount" 2>/dev/null
    if [ $? -eq 0 ]; then
        lan_log "NFS v4 mounted: ${server_ip}:${remote_path} -> $local_mount"
        return 0
    fi

    lan_log "NFS mount failed: ${server_ip}:${remote_path}"
    return 1
}

# ============================================
# SERVER: Main LAN Server function
# ============================================
do_lan_server() {
    clear
    echo "" > "$LAN_LOG"

    dialog --title "LAN Server" --yesno \
        "Start LAN Clone Server?\n\n\
This will:\n\
1. Use the largest internal HDD/SSD\n\
   as shared storage\n\
2. Start NFS server for LAN access\n\
3. Other PCs can clone/install via LAN\n\n\
WARNING: The largest disk may be\n\
formatted if no ext4 partition exists!" 16 55
    [ $? -ne 0 ] && return

    # Step 1: Detect disk
    dialog --infobox "\n  [1/4] Detecting storage..." 5 40
    lan_detect_largest_disk
    if [ $? -ne 0 ]; then
        dialog --msgbox "No internal disk found!\n\nConnect an internal HDD/SSD." 8 45
        return
    fi

    local disk_size
    disk_size=$(lsblk -d -o SIZE "$LAN_DISK_DEV" 2>/dev/null | tail -1 | tr -d ' ')
    local disk_model
    disk_model=$(lsblk -d -o MODEL "$LAN_DISK_DEV" 2>/dev/null | tail -1)
    lan_log "Detected disk: $LAN_DISK_DEV ($disk_size) $disk_model"

    # Step 2: Prepare storage
    dialog --infobox "\n  [2/4] Preparing storage on $LAN_DISK_DEV..." 5 55
    lan_prepare_storage "$LAN_DISK" "$LAN_NFS_PATH"
    if [ $? -ne 0 ]; then
        dialog --msgbox "Cannot prepare storage on $LAN_DISK_DEV!\n\nTry a different disk." 8 50
        return
    fi

    local storage_free
    storage_free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')

    # Step 3: Network
    dialog --infobox "\n  [3/4] Setting up network..." 5 40
    lan_get_ip
    if [ $? -ne 0 ]; then
        dialog --msgbox "No network interface found!\n\nConnect a LAN cable." 8 45
        umount "$LAN_NFS_PATH" 2>/dev/null
        return
    fi

    # Step 4: Start NFS + beacon
    dialog --infobox "\n  [4/4] Starting NFS server..." 5 40
    lan_start_nfs_server "$LAN_NFS_PATH"
    lan_start_beacon "$LAN_IP"

    # Show status dashboard
    lan_server_dashboard "$disk_size" "$disk_model" "$storage_free"

    # Cleanup on exit
    lan_stop_beacon
    lan_stop_nfs_server
    umount "$LAN_NFS_PATH" 2>/dev/null
    dialog --msgbox "LAN Server stopped." 6 30
}

# ============================================
# SERVER: Status dashboard (blocking loop)
# ============================================
lan_server_dashboard() {
    local disk_size="$1"
    local disk_model="$2"
    local storage_free="$3"

    while true; do
        # Count images on server
        local img_count=0
        local img_list=""
        if [ -d "$LAN_NFS_PATH" ]; then
            for dir in "$LAN_NFS_PATH"/*/; do
                [ -d "$dir" ] || continue
                if [ -f "${dir}disk" ] || [ -f "${dir}parts" ]; then
                    img_count=$((img_count + 1))
                    local iname
                    iname=$(basename "$dir")
                    local isize
                    isize=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    img_list="${img_list}  ${iname} (${isize})\n"
                fi
            done
        fi

        # Refresh free space
        storage_free=$(df -h "$LAN_NFS_PATH" 2>/dev/null | tail -1 | awk '{print $4}')

        # Count active NFS clients
        local client_count=0
        local client_list=""
        if command -v showmount >/dev/null 2>&1; then
            local clients
            clients=$(showmount --no-headers -a 2>/dev/null | cut -d: -f1 | sort -u)
            for c in $clients; do
                client_count=$((client_count + 1))
                client_list="${client_list}  ${c}\n"
            done
        fi

        # Build display
        local status_text=""
        status_text="${status_text}Server is running.\n\n"
        status_text="${status_text}IP Address:  $LAN_IP\n"
        status_text="${status_text}Interface:   $LAN_IF\n"
        status_text="${status_text}NFS Export:  $LAN_NFS_PATH\n"
        status_text="${status_text}Disk:        $LAN_DISK_DEV ($disk_size)\n"
        status_text="${status_text}Free Space:  $storage_free\n"
        status_text="${status_text}Discovery:   UDP port $LAN_PORT\n"
        status_text="${status_text}\n"
        status_text="${status_text}--- Images ($img_count) ---\n"
        if [ $img_count -gt 0 ]; then
            status_text="${status_text}${img_list}"
        else
            status_text="${status_text}  (none yet - clone a PC to save here)\n"
        fi
        status_text="${status_text}\n"
        status_text="${status_text}--- Connected Clients ($client_count) ---\n"
        if [ $client_count -gt 0 ]; then
            status_text="${status_text}${client_list}"
        else
            status_text="${status_text}  Waiting for clients...\n"
        fi
        status_text="${status_text}\n"
        status_text="${status_text}Time: $(date '+%H:%M:%S')\n"

        # Use --yes-label and --no-label for Refresh / Stop
        dialog --title "LAN Server Status" \
            --yes-label "Refresh" --no-label "Stop Server" \
            --yesno "$status_text" 28 60
        if [ $? -ne 0 ]; then
            # User chose Stop
            dialog --yesno "Stop LAN Server?" 6 30
            [ $? -eq 0 ] && return
        fi
    done
}

# ============================================
# CLIENT: Try to discover and mount NFS
#   Returns 0 if NFS mounted at /home/partimag
#   Sets LAN_CONNECTED=1
# ============================================
lan_try_nfs_for_clone() {
    LAN_CONNECTED=0

    # Quick UDP discovery (3 seconds)
    lan_discover_server 3
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Found server, try NFS mount
    lan_mount_nfs "$LAN_SERVER_IP" "$LAN_NFS_PATH" "/home/partimag"
    if [ $? -ne 0 ]; then
        lan_log "Server found at $LAN_SERVER_IP but NFS mount failed"
        return 1
    fi

    # Verify writable
    touch /home/partimag/.writetest 2>/dev/null
    if [ $? -ne 0 ]; then
        lan_log "NFS mount is not writable"
        umount /home/partimag 2>/dev/null
        return 1
    fi
    rm -f /home/partimag/.writetest

    LAN_CONNECTED=1
    lan_log "NFS clone target ready at $LAN_SERVER_IP"
    return 0
}

lan_try_nfs_for_install() {
    LAN_CONNECTED=0

    # Quick UDP discovery (3 seconds)
    lan_discover_server 3
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Found server, try NFS mount (read-only is fine for install)
    lan_mount_nfs "$LAN_SERVER_IP" "$LAN_NFS_PATH" "/home/partimag"
    if [ $? -ne 0 ]; then
        lan_log "Server found at $LAN_SERVER_IP but NFS mount failed"
        return 1
    fi

    # Check if there are any images
    local has_images=0
    for dir in /home/partimag/*/; do
        [ -d "$dir" ] || continue
        if [ -f "${dir}disk" ] || [ -f "${dir}parts" ]; then
            has_images=1
            break
        fi
    done

    if [ $has_images -eq 0 ]; then
        lan_log "NFS mounted but no images found on server"
        umount /home/partimag 2>/dev/null
        return 1
    fi

    LAN_CONNECTED=1
    lan_log "NFS install source ready at $LAN_SERVER_IP"
    return 0
}

# ============================================
# Select image from NFS mount (already mounted
#   at /home/partimag)
# ============================================
lan_select_nfs_image() {
    SEL_IMG_NAME=""
    local opts=""
    local count=0
    local img_map="/tmp/_lan_img_map"
    > "$img_map"

    for dir in /home/partimag/*/; do
        [ -d "$dir" ] || continue
        if [ -f "${dir}disk" ] || [ -f "${dir}parts" ]; then
            count=$((count + 1))
            local name
            name=$(basename "$dir")
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local note=""
            [ -f "/home/partimag/.note_${name}" ] && note=" - $(cat "/home/partimag/.note_${name}")"
            opts="$opts $count \"$name ($size)$note\""
            echo "$name" >> "$img_map"
        fi
    done

    if [ $count -eq 0 ]; then
        dialog --msgbox "No images on LAN server!" 6 35
        rm -f "$img_map"
        return 1
    fi

    # Auto-select if only one image
    if [ $count -eq 1 ]; then
        SEL_IMG_NAME=$(head -1 "$img_map")
        rm -f "$img_map"
        return 0
    fi

    local result
    result=$(eval "dialog --title \"Select Image (LAN)\" --menu \"\" 15 70 6 $opts" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { rm -f "$img_map"; return 1; }

    SEL_IMG_NAME=$(sed -n "${result}p" "$img_map")
    rm -f "$img_map"
    [ -z "$SEL_IMG_NAME" ] && return 1
    return 0
}
