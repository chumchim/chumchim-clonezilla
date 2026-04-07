#!/bin/bash
# ============================================
#   ChumChim-Clonezilla v3.0
#   Full dialog UI
# ============================================

# Re-run as root if not already
if [ "$(id -u)" != "0" ]; then
    exec sudo "$0" "$@"
fi

# Load multicast module
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/multicast-server.sh" ] && source "$SCRIPT_DIR/multicast-server.sh"
[ -f "/usr/local/bin/multicast-server.sh" ] && source "/usr/local/bin/multicast-server.sh"

LOG_FILE="/tmp/chumchim.log"
BOOT_USB=""

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }

# Friendly name for a device (single lsblk call)
friendly_name() {
    local DEV="$1"
    local DISK=$(echo "$DEV" | sed 's/[0-9]*$//;s/p[0-9]*$//')
    local INFO=$(lsblk -d -n -o MODEL,SIZE,RM "$DISK" 2>/dev/null | head -1)
    local MODEL=$(echo "$INFO" | awk '{$NF=""; $(NF-1)=""; print}' | sed 's/^ *//;s/ *$//')
    local DSIZE=$(echo "$INFO" | awk '{print $(NF-1)}')
    local RM=$(echo "$INFO" | awk '{print $NF}')
    local TYPE="Disk"
    [ "$RM" = "1" ] && TYPE="USB"
    [ "$DISK" = "$BOOT_USB" ] && TYPE="USB Boot"
    echo "$TYPE: $MODEL $DSIZE ($DEV)"
}

# Calculate used space on a disk (handles unmounted NTFS/NVMe)
get_src_used_mb() {
    local DISK="$1"
    local TOTAL=0
    for spart in /dev/${DISK}[0-9]* /dev/${DISK}p[0-9]*; do
        [ -b "$spart" ] || continue
        mkdir -p /tmp/_scheck
        mount -o ro "$spart" /tmp/_scheck 2>/dev/null
        if [ $? -eq 0 ]; then
            local USED=$(df -m /tmp/_scheck 2>/dev/null | tail -1 | awk '{print $3}')
            [ -n "$USED" ] && TOTAL=$((TOTAL + USED))
            umount /tmp/_scheck 2>/dev/null
        else
            local PSIZE=$(($(blockdev --getsize64 "$spart" 2>/dev/null) / 1048576))
            [ -n "$PSIZE" ] && TOTAL=$((TOTAL + PSIZE))
        fi
    done
    rmdir /tmp/_scheck 2>/dev/null
    echo $TOTAL
}

# Shutdown with fallbacks
do_shutdown() {
    do_shutdown
}

# ============================================
# Find boot USB (to exclude from selection)
# ============================================
find_boot_usb() {
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        mkdir -p /tmp/_boot 2>/dev/null
        mount $dev /tmp/_boot 2>/dev/null
        if [ -d "/tmp/_boot/live" ]; then
            BOOT_USB=$(echo $dev | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
            umount /tmp/_boot 2>/dev/null
            return
        fi
        umount /tmp/_boot 2>/dev/null
    done
}

# ============================================
# Auto-detect Windows disk
# ============================================
detect_windows_disk() {
    WIN_DISK=""
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        mkdir -p /tmp/_win 2>/dev/null
        mount -o ro $dev /tmp/_win 2>/dev/null
        if [ -d "/tmp/_win/Windows/System32" ]; then
            WIN_DISK=$(echo $dev | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | sed 's|/dev/||')
            umount /tmp/_win 2>/dev/null
            return 0
        fi
        umount /tmp/_win 2>/dev/null
    done
    return 1
}

# ============================================
# Dialog: Select Disk
# ============================================
select_disk() {
    TITLE=$1; [ -z "$TITLE" ] && TITLE="Select Disk"
    EXCLUDE_BOOT=$2  # "no" = show boot USB too
    SEL_DISK=""
    OPTS=""
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        TAG=""
        if [ "/dev/$dname" = "$BOOT_USB" ]; then
            [ "$EXCLUDE_BOOT" != "no" ] && continue
            TAG=" [BOOT]"
        fi
        # Tag Windows disk
        if [ -n "$WIN_DISK" ] && [ "$dname" = "$WIN_DISK" ]; then
            TAG="$TAG [WIN]"
        fi
        DSIZE=$(lsblk -d -o SIZE /dev/$dname 2>/dev/null | tail -1)
        DMODEL=$(lsblk -d -o MODEL /dev/$dname 2>/dev/null | tail -1)
        OPTS="$OPTS $dname \"$DSIZE  $DMODEL$TAG\""
    done
    [ -z "$OPTS" ] && { dialog --msgbox "No disks found!" 6 30; return 1; }
    SEL_DISK=$(eval "dialog --title \"$TITLE\" --menu \"Use arrow keys:\" 15 60 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    [ -z "$SEL_DISK" ] && return 1
    return 0
}

# ============================================
# Dialog: Select Partition
# ============================================
select_partition() {
    DISK=$1; SEL_PART=""
    OPTS=""; PCOUNT=0
    for pname in $(lsblk -l -o NAME /dev/$DISK 2>/dev/null | tail -n +2 | grep -v "^${DISK}$"); do
        PCOUNT=$((PCOUNT + 1))
        PSIZE=$(lsblk -o SIZE /dev/$pname 2>/dev/null | tail -1)
        PFS=$(lsblk -o FSTYPE /dev/$pname 2>/dev/null | tail -1)
        OPTS="$OPTS $pname \"$PSIZE  $PFS\""
    done
    [ $PCOUNT -eq 0 ] && { dialog --msgbox "No partitions on $DISK" 6 40; return 1; }
    [ $PCOUNT -eq 1 ] && { SEL_PART=$(lsblk -l -o NAME /dev/$DISK 2>/dev/null | tail -1); return 0; }
    SEL_PART=$(eval "dialog --title \"Partition on $DISK\" --menu \"\" 15 60 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    return 0
}

# ============================================
# Dialog: Select Image
# ============================================
select_image() {
    SEL_IMG_NAME=""; SEL_IMG_DEV=""
    local -a IMG_DEVS=()
    local -a IMG_NAMES=()
    OPTS=""; IMG_COUNT=0
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        mkdir -p /tmp/_sel 2>/dev/null
        mount $dev /tmp/_sel 2>/dev/null || continue
        for dir in /tmp/_sel/*/; do
            if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                IMG_COUNT=$((IMG_COUNT + 1))
                NAME=$(basename "$dir")
                SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                NOTE=""; [ -f "/tmp/_sel/.note_${NAME}" ] && NOTE=" - $(cat "/tmp/_sel/.note_${NAME}")"
                OPTS="$OPTS $IMG_COUNT \"$NAME ($SIZE)$NOTE\""
                IMG_DEVS[$IMG_COUNT]="$dev"
                IMG_NAMES[$IMG_COUNT]="$NAME"
            fi
        done
        umount /tmp/_sel 2>/dev/null
    done
    [ $IMG_COUNT -eq 0 ] && { dialog --msgbox "No images found!\n\nClone a PC first." 8 40; return 1; }
    RESULT=$(eval "dialog --title \"Select Image\" --menu \"\" 15 70 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    SEL_IMG_DEV="${IMG_DEVS[$RESULT]}"
    SEL_IMG_NAME="${IMG_NAMES[$RESULT]}"
    return 0
}

# ============================================
# Verify image
# ============================================
verify_image() {
    DIR="$1"
    if [ -f "$DIR/disk" ] && [ -f "$DIR/parts" ]; then
        for part in $(cat "$DIR/parts"); do
            [ -z "$(ls "$DIR/" | grep "^${part}\." 2>/dev/null)" ] && return 1
        done
        return 0
    fi
    return 1
}

# ============================================
# CLONE: Auto-detect source + save
# ============================================
clone_auto_detect() {
    SRC=""; SAVE_DEV=""
    detect_windows_disk

    # Auto-detect source: use Windows disk
    if [ -n "$WIN_DISK" ]; then
        SRC=$WIN_DISK
    else
        # No Windows found, pick the first non-USB disk
        for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
            [ "/dev/$dname" = "$BOOT_USB" ] && continue
            SRC=$dname; break
        done
    fi
    [ -z "$SRC" ] && { dialog --msgbox "No source disk found!" 8 40; return 1; }

    # Auto-detect save: Priority order:
    # 1. USB/removable with enough space -> best (portable)
    # 2. Other internal disk with enough space -> fallback
    SAVE_DEV=""
    BEST_USB_DEV=""; BEST_USB_FREE=0
    BEST_INT_DEV=""; BEST_INT_FREE=0

    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        [ "$dname" = "$SRC" ] && continue
        REMOVABLE=$(lsblk -d -o RM /dev/$dname 2>/dev/null | tail -1 | tr -d ' ')
        for pname in $(lsblk -l -o NAME /dev/$dname 2>/dev/null | tail -n +2 | grep -v "^${dname}$"); do
            FS=$(blkid -o value -s TYPE /dev/$pname 2>/dev/null)
            [ "$FS" = "iso9660" ] && continue
            [ "$FS" = "squashfs" ] && continue
            PSIZE=$(($(blockdev --getsize64 /dev/$pname 2>/dev/null) / 1048576))
            [ "$PSIZE" -lt 100 ] && continue
            mkdir -p /tmp/_autocheck
            mount /dev/$pname /tmp/_autocheck 2>/dev/null || continue
            touch /tmp/_autocheck/.writetest 2>/dev/null
            if [ $? -eq 0 ]; then
                rm -f /tmp/_autocheck/.writetest
                FREE_MB=$(df -m /tmp/_autocheck 2>/dev/null | tail -1 | awk '{print $4}')
                [ -z "$FREE_MB" ] && FREE_MB=0
                if [ "$REMOVABLE" = "1" ] || [ "/dev/$dname" = "$BOOT_USB" ]; then
                    # USB/removable
                    if [ "$FREE_MB" -gt "$BEST_USB_FREE" ]; then
                        BEST_USB_FREE=$FREE_MB
                        BEST_USB_DEV="/dev/$pname"
                    fi
                else
                    # Internal disk
                    if [ "$FREE_MB" -gt "$BEST_INT_FREE" ]; then
                        BEST_INT_FREE=$FREE_MB
                        BEST_INT_DEV="/dev/$pname"
                    fi
                fi
            fi
            umount /tmp/_autocheck 2>/dev/null
        done
    done

    # Choose: prefer USB if it has enough space, else use internal
    if [ -n "$BEST_USB_DEV" ] && [ "$BEST_USB_FREE" -gt 0 ]; then
        SAVE_DEV="$BEST_USB_DEV"
        SAVE_FREE_DETECTED=$BEST_USB_FREE
    elif [ -n "$BEST_INT_DEV" ] && [ "$BEST_INT_FREE" -gt 0 ]; then
        SAVE_DEV="$BEST_INT_DEV"
        SAVE_FREE_DETECTED=$BEST_INT_FREE
    fi

    if [ -z "$SAVE_DEV" ]; then
        dialog --msgbox "No writable disk found!\n\nPlug in USB or External HDD\nand try again." 10 50
        return 1
    fi
    log "Auto-detect save: $SAVE_DEV ($(friendly_name $SAVE_DEV))"

    # Mount save
    mkdir -p /home/partimag
    mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV\nTry format USB as NTFS or ext4" 8 50; return 1; }

    # Auto image name
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1 | tr -d ' ')
    DEFAULT_NAME="Clone-$(date +%d%b)-${SRC_SIZE}"

    # Single screen: name + note
    IMG_NAME=$(dialog --title "Image Name" --inputbox \
        "Detected:\n  Source: /dev/$SRC ($SRC_SIZE)\n  Save:   $SAVE_DEV\n\nImage name:" \
        12 55 "$DEFAULT_NAME" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    [ -z "$IMG_NAME" ] && IMG_NAME="$DEFAULT_NAME"

    IMG_NOTE=$(dialog --title "Note (press OK to skip)" --inputbox \
        "Installed software e.g. Win11+Office+Adobe:" \
        8 55 "" 3>&1 1>&2 2>&3)
    [ -n "$IMG_NOTE" ] && echo "$IMG_NOTE" > /home/partimag/.note_${IMG_NAME}

    # Check existing
    if [ -d "/home/partimag/$IMG_NAME" ]; then
        dialog --yesno "Image '$IMG_NAME' already exists!\n\nOverwrite?" 8 40 || { umount /home/partimag 2>/dev/null; return 1; }
        rm -rf "/home/partimag/$IMG_NAME"
    fi

    # Check free space
    SAVE_FREE_MB=$(df -m /home/partimag 2>/dev/null | tail -1 | awk '{print $4}')
    [ -z "$SAVE_FREE_MB" ] && SAVE_FREE_MB=0
    SRC_USED_MB=$(get_src_used_mb "$SRC")

    SAVE_FREE_GB=$((SAVE_FREE_MB / 1024))
    SRC_USED_GB=$((SRC_USED_MB / 1024))
    # Estimate compressed image size (~40% of used)
    EST_IMAGE_MB=$((SRC_USED_MB * 40 / 100))
    EST_IMAGE_GB=$((EST_IMAGE_MB / 1024))

    # If USB doesn't have enough space, auto-switch to internal disk
    if [ "$SAVE_FREE_MB" -gt 0 ] && [ "$SRC_USED_MB" -gt 0 ]; then
        if [ "$SAVE_FREE_MB" -lt "$((SRC_USED_MB / 4))" ]; then
            # Current save is too small — try internal disk
            if [ -n "$BEST_INT_DEV" ] && [ "$BEST_INT_FREE" -gt "$((SRC_USED_MB / 4))" ]; then
                umount /home/partimag 2>/dev/null
                SAVE_DEV="$BEST_INT_DEV"
                mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV" 6 40; return 1; }
                SAVE_FREE_MB=$BEST_INT_FREE
                SAVE_FREE_GB=$((SAVE_FREE_MB / 1024))
                log "Auto-switched to internal: $SAVE_DEV (${SAVE_FREE_GB}GB free)"
            else
                umount /home/partimag 2>/dev/null
                dialog --msgbox "NOT ENOUGH SPACE!\n\nSource used:     ~${SRC_USED_GB} GB\nEstimated image: ~${EST_IMAGE_GB} GB\nSave free:       ~${SAVE_FREE_GB} GB\n\nNeed USB or External HDD\nwith ~${EST_IMAGE_GB}GB+ free." 16 55
                return 1
            fi
        fi
    fi

    # Auto-select compression based on free space
    if [ "$SAVE_FREE_MB" -gt 0 ] && [ "$SRC_USED_MB" -gt 0 ]; then
        RATIO=$((SAVE_FREE_MB * 100 / SRC_USED_MB))
        if [ "$RATIO" -gt 150 ]; then
            COMPRESS="-z0"   # Plenty of space: no compression = fastest
            SPEED_INFO="Fast (no compression)"
        elif [ "$RATIO" -gt 80 ]; then
            COMPRESS="-z3"   # Enough space: lz4 = fast + good ratio
            SPEED_INFO="Normal (lz4)"
        else
            COMPRESS="-z5p"  # Tight space: xz = smallest image
            SPEED_INFO="Max compress (xz, slower but smallest)"
        fi
    else
        COMPRESS="-z3"
        SPEED_INFO="Normal (lz4)"
    fi

    # Confirm
    SAVE_FRIENDLY=$(friendly_name "$SAVE_DEV")
    SRC_FRIENDLY=$(friendly_name "/dev/$SRC")
    dialog --yesno "Start clone?\n\nFrom: $SRC_FRIENDLY\nTo:   $SAVE_FRIENDLY\nName: $IMG_NAME\nNote: ${IMG_NOTE:-none}\nSpeed: $SPEED_INFO\nFree: ~${SAVE_FREE_GB} GB" 16 60
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    return 0
}

# ============================================
# CLONE: Manual select
# ============================================
clone_manual_select() {
    detect_windows_disk

    # Select source
    select_disk "Clone: Select SOURCE disk" || return 1
    SRC=$SEL_DISK

    # Select save disk + partition (show boot USB too)
    select_disk "Clone: Select SAVE disk" "no" || return 1
    SAVE=$SEL_DISK
    select_partition "$SAVE" || return 1

    # Prevent saving to same disk as source
    SAVE_BASE=$(echo "$SEL_PART" | sed 's/p\?[0-9]*$//')
    if [ "$SAVE_BASE" = "$SRC" ]; then
        dialog --msgbox "Cannot save to the same disk!\n\nSource: /dev/$SRC\nSave:   /dev/$SEL_PART" 10 50
        return 1
    fi

    SAVE_DEV="/dev/$SEL_PART"
    mkdir -p /home/partimag
    mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV" 6 40; return 1; }

    # Check free space
    SAVE_FREE_MB=$(df -m /home/partimag 2>/dev/null | tail -1 | awk '{print $4}')
    [ -z "$SAVE_FREE_MB" ] && SAVE_FREE_MB=0
    SRC_USED_MB=$(get_src_used_mb "$SRC")
    SAVE_FREE_GB=$((SAVE_FREE_MB / 1024))
    SRC_USED_GB=$((SRC_USED_MB / 1024))
    EST_IMAGE_GB=$((SRC_USED_MB * 40 / 100 / 1024))

    if [ "$SAVE_FREE_MB" -gt 0 ] && [ "$SRC_USED_MB" -gt 0 ]; then
        if [ "$SAVE_FREE_MB" -lt "$((SRC_USED_MB / 4))" ]; then
            dialog --yesno "WARNING: Low disk space!\n\nSource used:     ~${SRC_USED_GB} GB\nEstimated image: ~${EST_IMAGE_GB} GB\nSave free:       ~${SAVE_FREE_GB} GB\n\nContinue anyway?" 14 55
            [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
        fi
    fi

    # Image name
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1 | tr -d ' ')
    IMG_NAME=$(dialog --title "Image Name" --inputbox "Name:" 8 50 "Room$(date +%m%d)" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    [ -z "$IMG_NAME" ] && IMG_NAME="Image-$(date +%Y%m%d-%H%M)"

    # Note
    IMG_NOTE=$(dialog --title "Note (press OK to skip)" --inputbox "Installed software:" 8 55 "" 3>&1 1>&2 2>&3)
    [ -n "$IMG_NOTE" ] && echo "$IMG_NOTE" > /home/partimag/.note_${IMG_NAME}

    # Check existing
    if [ -d "/home/partimag/$IMG_NAME" ]; then
        dialog --yesno "Image '$IMG_NAME' already exists!\n\nOverwrite?" 8 40 || { umount /home/partimag 2>/dev/null; return 1; }
        rm -rf "/home/partimag/$IMG_NAME"
    fi

    # Speed
    SPEED=$(dialog --title "Clone Speed" --menu "" 10 50 3 \
        1 "Fast    (larger file, faster)" \
        2 "Normal  (balanced, recommended)" \
        3 "Small   (smaller file, slower)" \
        3>&1 1>&2 2>&3)
    case $SPEED in
        1) COMPRESS="-z0" ;;
        3) COMPRESS="-z5p" ;;
        *) COMPRESS="-z3" ;;
    esac

    # Confirm
    dialog --yesno "Start clone?\n\nSource:  /dev/$SRC ($SRC_SIZE)\nSave to: $SAVE_DEV\nName:    $IMG_NAME\nNote:    ${IMG_NOTE:-none}\nFree:    ~${SAVE_FREE_GB} GB" 14 55
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    return 0
}

# ============================================
# CLONE
# ============================================
do_clone() {
    clear
    log "Starting clone..."

    # Choose mode
    MODE=$(dialog --title "Clone this PC" --menu "Select mode:" 12 55 2 \
        1 "Auto     (auto-detect, recommended)" \
        2 "Manual   (select everything manually)" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    case $MODE in
        1) clone_auto_detect || return ;;
        2) clone_manual_select || return ;;
        *) return ;;
    esac

    # Clone
    clear
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1 | tr -d ' ')
    PART_COUNT=$(lsblk -l -o NAME /dev/$SRC 2>/dev/null | tail -n +2 | grep -v "^${SRC}$" | wc -l)
    PART_LIST=$(lsblk -l -o NAME,SIZE,FSTYPE /dev/$SRC 2>/dev/null | tail -n +2 | grep -v "^${SRC} ")
    echo ""
    echo "  ============================================"
    echo "    CLONING: /dev/$SRC ($SRC_SIZE)"
    echo "    Save to: $SAVE_DEV -> $IMG_NAME"
    echo "    Partitions: $PART_COUNT"
    echo "    $PART_LIST"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""
    log "Clone /dev/$SRC -> $IMG_NAME ($PART_COUNT partitions)"

    /usr/sbin/ocs-sr -q2 -batch -nogui -j2 $COMPRESS -i 67108864 -sfsck -senc -p true savedisk "$IMG_NAME" "$SRC" 2>&1 | tee -a "$LOG_FILE"
    OCS_RC=${PIPESTATUS[0]}

    if [ $OCS_RC -eq 0 ]; then
        SIZE=$(du -sh /home/partimag/$IMG_NAME 2>/dev/null | cut -f1)
        if verify_image "/home/partimag/$IMG_NAME"; then
            log "Clone OK: $IMG_NAME ($SIZE)"
            SAVE_FRIENDLY=$(friendly_name "$SAVE_DEV")
            dialog --msgbox "CLONE COMPLETE!\n\nImage:  $IMG_NAME\nSize:   $SIZE\nSaved:  $SAVE_FRIENDLY\nFolder: $IMG_NAME\nNote:   ${IMG_NOTE:-none}" 14 60
        else
            log "Clone WARN: image verification failed"
            dialog --msgbox "Clone finished but verification FAILED!\n\nImage may be incomplete.\nCheck log: $LOG_FILE" 10 50
        fi
    else
        log "Clone FAILED"
        LAST_ERR=$(tail -30 "$LOG_FILE" 2>/dev/null)
        dialog --title "CLONE FAILED" --msgbox "Clone failed!\n\nLast log entries:\n$LAST_ERR" 20 70
    fi

    umount /home/partimag 2>/dev/null

    do_shutdown
}

# ============================================
# INSTALL: Auto-detect
# ============================================
install_auto_detect() {
    # Find image automatically
    select_image || return 1

    mkdir -p /home/partimag
    mount $SEL_IMG_DEV /home/partimag 2>/dev/null
    IMG_NAME=$SEL_IMG_NAME

    # Auto-detect target: find the largest internal (non-removable, non-boot) disk
    TGT=""
    TGT_SIZE_BYTES=0
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        # Skip boot USB
        [ "/dev/$dname" = "$BOOT_USB" ] && continue
        # Skip disk that has the image
        IMG_BASE=$(echo "$SEL_IMG_DEV" | sed 's/[0-9]*$//;s/p[0-9]*$//' | sed 's|/dev/||')
        [ "$dname" = "$IMG_BASE" ] && continue
        # Skip removable/USB disks (don't install to USB by accident)
        RM=$(lsblk -d -o RM /dev/$dname 2>/dev/null | tail -1 | tr -d ' ')
        [ "$RM" = "1" ] && continue
        # Pick the largest internal disk
        DSIZE=$(blockdev --getsize64 /dev/$dname 2>/dev/null)
        [ -z "$DSIZE" ] && continue
        if [ "$DSIZE" -gt "$TGT_SIZE_BYTES" ]; then
            TGT_SIZE_BYTES=$DSIZE
            TGT=$dname
        fi
    done

    if [ -z "$TGT" ]; then
        dialog --msgbox "No target disk found!\n\nOnly the boot USB and image disk\nwere detected." 10 50
        umount /home/partimag 2>/dev/null
        return 1
    fi

    TGT_SIZE=$(lsblk -d -o SIZE /dev/$TGT 2>/dev/null | tail -1)
    TGT_MODEL=$(lsblk -d -o MODEL /dev/$TGT 2>/dev/null | tail -1)

    # Confirm with clear summary
    dialog --yesno "Install image to this PC?\n\nImage:   $IMG_NAME\nTarget:  /dev/$TGT ($TGT_SIZE)\nModel:   $TGT_MODEL\n\n*** ALL DATA ON /dev/$TGT WILL BE ERASED! ***" 14 55
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    return 0
}

# ============================================
# INSTALL: Manual select
# ============================================
install_manual_select() {
    select_image || return 1

    mkdir -p /home/partimag
    mount $SEL_IMG_DEV /home/partimag 2>/dev/null
    IMG_NAME=$SEL_IMG_NAME

    # Select target
    select_disk "Install: Select TARGET disk (ERASED!)" || { umount /home/partimag 2>/dev/null; return 1; }
    TGT=$SEL_DISK

    # Disk health
    HEALTH=$(smartctl -H /dev/$TGT 2>/dev/null | grep -i "result" | awk '{print $NF}')
    if [ "$HEALTH" = "FAILED" ]; then
        dialog --yesno "WARNING: Disk health FAILING!\n\nContinue anyway?" 8 40 || { umount /home/partimag 2>/dev/null; return 1; }
    fi

    TGT_SIZE=$(lsblk -d -o SIZE /dev/$TGT 2>/dev/null | tail -1)
    TGT_MODEL=$(lsblk -d -o MODEL /dev/$TGT 2>/dev/null | tail -1)
    dialog --yesno "Install image to this disk?\n\nImage:  $IMG_NAME\nTarget: /dev/$TGT ($TGT_SIZE)\nModel:  $TGT_MODEL\n\nALL DATA WILL BE ERASED!" 14 50
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return 1; }
    return 0
}

# ============================================
# INSTALL
# ============================================
do_install() {
    clear
    log "Starting install..."

    # Choose mode
    MODE=$(dialog --title "Install to PC" --menu "Select mode:" 12 55 2 \
        1 "Auto     (auto-detect target, recommended)" \
        2 "Manual   (select everything manually)" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    case $MODE in
        1) install_auto_detect || return ;;
        2) install_manual_select || return ;;
        *) return ;;
    esac

    # Install
    clear
    PART_COUNT=0
    [ -f "/home/partimag/$IMG_NAME/parts" ] && PART_COUNT=$(wc -w < "/home/partimag/$IMG_NAME/parts")
    echo ""
    echo "  ============================================"
    echo "    INSTALLING: $IMG_NAME -> /dev/$TGT"
    echo "    Partitions: $PART_COUNT"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""
    log "Install $IMG_NAME -> /dev/$TGT ($PART_COUNT partitions)"

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -batch -nogui -j2 -p true restoredisk "$IMG_NAME" "$TGT" 2>&1 | tee -a "$LOG_FILE"
    OCS_RC=${PIPESTATUS[0]}

    if [ $OCS_RC -eq 0 ]; then
        log "Install OK: $IMG_NAME -> /dev/$TGT"
        dialog --msgbox "INSTALL COMPLETE!\n\nRemove USB and restart." 8 40
    else
        log "Install FAILED"
        LAST_ERR=$(tail -30 "$LOG_FILE" 2>/dev/null)
        dialog --title "INSTALL FAILED" --msgbox "Install failed!\n\nLast log entries:\n$LAST_ERR" 20 70
    fi

    umount /home/partimag 2>/dev/null

    dialog --yesno "Shutdown computer?" 6 30 && { sync; shutdown -h now 2>/dev/null || poweroff 2>/dev/null || halt 2>/dev/null || echo o > /proc/sysrq-trigger; }
}

# ============================================
# MANAGE IMAGES
# ============================================
do_manage() {
    while true; do
        ACTION=$(dialog --title "Manage Images" --menu "" 14 50 5 \
            1 "View all images" \
            2 "Copy image to another disk" \
            3 "Delete an image" \
            4 "Add/edit note" \
            0 "Back" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return
        case $ACTION in
            1)
                INFO=""
                for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
                    mkdir -p /tmp/_v 2>/dev/null
                    mount $dev /tmp/_v 2>/dev/null
                    for dir in /tmp/_v/*/; do
                        if [ -f "${dir}disk" ] 2>/dev/null; then
                            NAME=$(basename $dir)
                            SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                            DATE=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1)
                            NOTE=""; [ -f "/tmp/_v/.note_${NAME}" ] && NOTE=$(cat "/tmp/_v/.note_${NAME}")
                            INFO="$INFO$NAME  ($SIZE)  $DATE\n$NOTE\n\n"
                        fi
                    done
                    umount /tmp/_v 2>/dev/null
                done
                [ -z "$INFO" ] && INFO="No images found."
                dialog --title "All Images" --msgbox "$INFO" 20 60
                ;;
            2)
                # Copy Image to another disk
                select_image || continue
                SRC_IMG_DEV=$SEL_IMG_DEV
                SRC_IMG_NAME=$SEL_IMG_NAME

                # Mount source
                mkdir -p /tmp/_csrc
                mount $SRC_IMG_DEV /tmp/_csrc 2>/dev/null || { dialog --msgbox "Cannot mount source" 6 40; continue; }
                IMG_SIZE=$(du -sh "/tmp/_csrc/$SRC_IMG_NAME" 2>/dev/null | cut -f1)

                # Select destination disk
                select_disk "Copy to: Select DESTINATION disk" "no" || { umount /tmp/_csrc 2>/dev/null; continue; }
                DST_DISK=$SEL_DISK
                select_partition "$DST_DISK" || { umount /tmp/_csrc 2>/dev/null; continue; }
                DST_DEV="/dev/$SEL_PART"

                # Prevent copy to same partition
                if [ "$DST_DEV" = "$SRC_IMG_DEV" ]; then
                    dialog --msgbox "Cannot copy to the same disk!\nChoose a different disk." 8 45
                    umount /tmp/_csrc 2>/dev/null
                    continue
                fi

                # Mount destination
                mkdir -p /tmp/_cdst
                mount $DST_DEV /tmp/_cdst 2>/dev/null || { dialog --msgbox "Cannot mount $DST_DEV\nTry NTFS or ext4 formatted disk." 8 45; umount /tmp/_csrc 2>/dev/null; continue; }

                # Check free space
                DST_FREE=$(df -h /tmp/_cdst 2>/dev/null | tail -1 | awk '{print $4}')

                # Confirm
                dialog --yesno "Copy image?\n\nImage: $SRC_IMG_NAME ($IMG_SIZE)\nFrom:  $SRC_IMG_DEV\nTo:    $DST_DEV (free: $DST_FREE)\n\nThis may take a few minutes." 14 55
                if [ $? -ne 0 ]; then
                    umount /tmp/_cdst 2>/dev/null
                    umount /tmp/_csrc 2>/dev/null
                    continue
                fi

                # Copy
                clear
                echo ""
                echo "  ============================================"
                echo "    COPYING: $SRC_IMG_NAME ($IMG_SIZE)"
                echo "    From: $SRC_IMG_DEV"
                echo "    To:   $DST_DEV"
                echo "    DO NOT unplug any drive!"
                echo "  ============================================"
                echo ""

                # Check if exists on destination
                if [ -d "/tmp/_cdst/$SRC_IMG_NAME" ]; then
                    rm -rf "/tmp/_cdst/$SRC_IMG_NAME"
                fi

                cp -a "/tmp/_csrc/$SRC_IMG_NAME" "/tmp/_cdst/" 2>&1
                CP_RC=$?

                # Copy note too
                [ -f "/tmp/_csrc/.note_${SRC_IMG_NAME}" ] && cp "/tmp/_csrc/.note_${SRC_IMG_NAME}" "/tmp/_cdst/"

                umount /tmp/_cdst 2>/dev/null
                umount /tmp/_csrc 2>/dev/null

                if [ $CP_RC -eq 0 ]; then
                    dialog --msgbox "COPY COMPLETE!\n\nImage: $SRC_IMG_NAME\nCopied to: $DST_DEV" 10 50
                else
                    dialog --msgbox "COPY FAILED!\n\nDisk may be full or disconnected." 8 45
                fi
                ;;
            3)
                select_image || continue
                dialog --yesno "DELETE image:\n$SEL_IMG_NAME\n\nThis cannot be undone!" 10 40 || continue
                mkdir -p /tmp/_del
                mount $SEL_IMG_DEV /tmp/_del 2>/dev/null || { dialog --msgbox "Cannot mount device" 6 40; continue; }
                rm -rf "/tmp/_del/$SEL_IMG_NAME"
                rm -f "/tmp/_del/.note_${SEL_IMG_NAME}"
                umount /tmp/_del 2>/dev/null
                dialog --msgbox "Deleted: $SEL_IMG_NAME" 6 40
                ;;
            4)
                select_image || continue
                NOTE=$(dialog --title "Note for $SEL_IMG_NAME" --inputbox "" 8 60 "" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                mkdir -p /tmp/_note
                mount $SEL_IMG_DEV /tmp/_note 2>/dev/null || { dialog --msgbox "Cannot mount device" 6 40; continue; }
                echo "$NOTE" > "/tmp/_note/.note_${SEL_IMG_NAME}"
                umount /tmp/_note 2>/dev/null
                dialog --msgbox "Note saved!" 6 30
                ;;
            0) return ;;
        esac
    done
}

# ============================================
# HELP
# ============================================
show_help() {
    dialog --title "Help" --msgbox "\
ChumChim-Clonezilla v3.0\n\n\
[1] Clone this PC\n\
    Copy everything (Windows, programs, files)\n\
    from this PC into an image file.\n\n\
[2] Install to PC\n\
    Take an image and install it to this PC.\n\
    WARNING: erases everything on target disk.\n\n\
[3] Deploy to many PCs\n\
    Use LAN to install image to many PCs\n\
    at once (Multicast).\n\n\
Workflow:\n\
  1. Install software on one PC\n\
  2. Clone it\n\
  3. Install to other PCs\n\
  4. Done!" 22 55
}

# ============================================
# SPLASH
# ============================================
show_splash() {
    dialog --title "" --infobox "\n\n\
    ChumChim-Clonezilla v3.0\n\n\
    PC Clone & Deploy Tool\n\n\
    Based on Clonezilla\n\
    github.com/chumchim\n\n\
    Loading..." 14 45
    sleep 1
}

# ============================================
# MAIN
# ============================================
find_boot_usb
show_splash

while true; do
    choice=$(dialog --title "ChumChim-Clonezilla v3.0" \
        --menu "Select:" 15 55 6 \
        1 "Clone this PC       (save as image)" \
        2 "Install to PC       (install image)" \
        3 "Deploy to many PCs  (LAN Multicast)" \
        4 "Manage Images" \
        5 "Help" \
        0 "Shutdown" \
        3>&1 1>&2 2>&3)

    case $choice in
        1) do_clone ;;
        2) do_install ;;
        3) do_multicast 2>/dev/null || dialog --msgbox "Multicast not ready.\nUse USB method instead." 8 40 ;;
        4) do_manage ;;
        5) show_help ;;
        0) do_shutdown ;;
        *) continue ;;
    esac
done
