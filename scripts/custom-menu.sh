#!/bin/bash
# ============================================
#   ChumChim-Clonezilla v3.0
#   Simple & Clean UI — Auto everything
# ============================================

# Re-run as root if not already
if [ "$(id -u)" != "0" ]; then
    exec sudo "$0" "$@"
fi

# Load modules
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/lan-server.sh" ] && source "$SCRIPT_DIR/lan-server.sh"
[ -f "/usr/local/bin/lan-server.sh" ] && source "/usr/local/bin/lan-server.sh"

LOG_FILE="/tmp/chumchim.log"
BOOT_USB=""
WIN_DISK=""

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

# Calculate used space on a disk
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
    dialog --yesno "Shutdown?" 6 30 && { sync; shutdown -h now 2>/dev/null || poweroff 2>/dev/null || halt 2>/dev/null || echo o > /proc/sysrq-trigger; }
}

# ============================================
# Find boot USB (to exclude from selection)
# ============================================
find_boot_usb() {
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        [ -b "$dev" ] || continue
        mkdir -p /tmp/_boot 2>/dev/null
        mount -o ro "$dev" /tmp/_boot 2>/dev/null || continue
        if [ -d "/tmp/_boot/live" ]; then
            BOOT_USB=$(echo "$dev" | sed 's/[0-9]*$//;s/p[0-9]*$//')
            umount /tmp/_boot 2>/dev/null
            rmdir /tmp/_boot 2>/dev/null
            return
        fi
        umount /tmp/_boot 2>/dev/null
    done
    rmdir /tmp/_boot 2>/dev/null
}

# ============================================
# Auto-detect Windows disk
# ============================================
detect_windows_disk() {
    WIN_DISK=""
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        [ -b "$dev" ] || continue
        mkdir -p /tmp/_win 2>/dev/null
        mount -o ro "$dev" /tmp/_win 2>/dev/null || continue
        if [ -d "/tmp/_win/Windows/System32" ]; then
            WIN_DISK=$(echo "$dev" | sed 's/[0-9]*$//;s/p[0-9]*$//' | sed 's|/dev/||')
            umount /tmp/_win 2>/dev/null
            rmdir /tmp/_win 2>/dev/null
            return 0
        fi
        umount /tmp/_win 2>/dev/null
    done
    rmdir /tmp/_win 2>/dev/null
    return 1
}

# ============================================
# Select image from any connected storage
# ============================================
select_image() {
    SEL_IMG_NAME=""; SEL_IMG_DEV=""
    local -a IMG_DEVS=()
    local -a IMG_NAMES=()
    local OPTS="" IMG_COUNT=0
    for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
        [ -b "$dev" ] || continue
        mkdir -p /tmp/_sel 2>/dev/null
        mount "$dev" /tmp/_sel 2>/dev/null || continue
        for dir in /tmp/_sel/*/; do
            if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                IMG_COUNT=$((IMG_COUNT + 1))
                local NAME=$(basename "$dir")
                local SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                local NOTE=""; [ -f "/tmp/_sel/.note_${NAME}" ] && NOTE=" - $(cat "/tmp/_sel/.note_${NAME}")"
                OPTS="$OPTS $IMG_COUNT \"$NAME ($SIZE)$NOTE\""
                IMG_DEVS[$IMG_COUNT]="$dev"
                IMG_NAMES[$IMG_COUNT]="$NAME"
            fi
        done
        umount /tmp/_sel 2>/dev/null
    done
    [ $IMG_COUNT -eq 0 ] && { dialog --msgbox "No images found!\n\nClone a PC first." 8 40; return 1; }
    # Auto-select if only 1 image
    if [ $IMG_COUNT -eq 1 ]; then
        SEL_IMG_DEV="${IMG_DEVS[1]}"
        SEL_IMG_NAME="${IMG_NAMES[1]}"
        return 0
    fi
    RESULT=$(eval "dialog --title \"Select Image\" --menu \"\" 15 70 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    SEL_IMG_DEV="${IMG_DEVS[$RESULT]}"
    SEL_IMG_NAME="${IMG_NAMES[$RESULT]}"
    return 0
}

# ============================================
# Verify image integrity
# ============================================
verify_image() {
    local DIR="$1"
    if [ -f "$DIR/disk" ] && [ -f "$DIR/parts" ]; then
        for part in $(cat "$DIR/parts"); do
            [ -z "$(ls "$DIR/" | grep "^${part}\." 2>/dev/null)" ] && return 1
        done
        return 0
    fi
    return 1
}

# ============================================
# CLONE (Auto — detect everything)
# ============================================
do_clone() {
    clear
    log "Starting clone..."
    detect_windows_disk

    # Auto-detect source: Windows disk or first non-USB disk
    SRC=""
    if [ -n "$WIN_DISK" ]; then
        SRC=$WIN_DISK
    else
        for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
            [ "/dev/$dname" = "$BOOT_USB" ] && continue
            SRC=$dname; break
        done
    fi
    [ -z "$SRC" ] && { dialog --msgbox "No source disk found!" 8 40; return; }

    # Try LAN NFS first (fastest)
    SAVE_VIA_LAN=0
    if type lan_try_nfs_for_clone >/dev/null 2>&1; then
        dialog --infobox "\n  Scanning LAN for server..." 5 40
        if lan_try_nfs_for_clone; then
            SAVE_VIA_LAN=1
            SAVE_DEV="LAN:${LAN_SERVER_IP}"
            SAVE_FREE_MB=$(df -m /home/partimag 2>/dev/null | tail -1 | awk '{print $4}')
            [ -z "$SAVE_FREE_MB" ] && SAVE_FREE_MB=999999
        fi
    fi

    # If no LAN, find local storage (prefer USB, fallback to internal)
    if [ "$SAVE_VIA_LAN" = "0" ]; then
        SAVE_DEV=""
        BEST_USB_DEV=""; BEST_USB_FREE=0
        BEST_INT_DEV=""; BEST_INT_FREE=0

        for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
            [ "$dname" = "$SRC" ] && continue
            local RM=$(lsblk -d -o RM /dev/$dname 2>/dev/null | tail -1 | tr -d ' ')
            for pname in $(lsblk -l -o NAME /dev/$dname 2>/dev/null | tail -n +2 | grep -v "^${dname}$"); do
                local FS=$(blkid -o value -s TYPE /dev/$pname 2>/dev/null)
                [ "$FS" = "iso9660" ] && continue
                [ "$FS" = "squashfs" ] && continue
                local PSIZE=$(($(blockdev --getsize64 /dev/$pname 2>/dev/null) / 1048576))
                [ "$PSIZE" -lt 100 ] && continue
                mkdir -p /tmp/_autocheck
                mount /dev/$pname /tmp/_autocheck 2>/dev/null || continue
                touch /tmp/_autocheck/.writetest 2>/dev/null
                if [ $? -eq 0 ]; then
                    rm -f /tmp/_autocheck/.writetest
                    local FREE_MB=$(df -m /tmp/_autocheck 2>/dev/null | tail -1 | awk '{print $4}')
                    [ -z "$FREE_MB" ] && FREE_MB=0
                    if [ "$RM" = "1" ] || [ "/dev/$dname" = "$BOOT_USB" ]; then
                        [ "$FREE_MB" -gt "$BEST_USB_FREE" ] && { BEST_USB_FREE=$FREE_MB; BEST_USB_DEV="/dev/$pname"; }
                    else
                        [ "$FREE_MB" -gt "$BEST_INT_FREE" ] && { BEST_INT_FREE=$FREE_MB; BEST_INT_DEV="/dev/$pname"; }
                    fi
                fi
                umount /tmp/_autocheck 2>/dev/null
            done
        done

        # Prefer USB, fallback to internal
        if [ -n "$BEST_USB_DEV" ]; then
            SAVE_DEV="$BEST_USB_DEV"; SAVE_FREE_MB=$BEST_USB_FREE
        elif [ -n "$BEST_INT_DEV" ]; then
            SAVE_DEV="$BEST_INT_DEV"; SAVE_FREE_MB=$BEST_INT_FREE
        fi

        [ -z "$SAVE_DEV" ] && { dialog --msgbox "No storage found!\n\nPlug in USB, External HDD,\nor start LAN Server on another PC." 10 50; return; }

        # Mount
        mkdir -p /home/partimag
        mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV" 6 40; return; }

        # Check space — if USB too small, try internal
        SRC_USED_MB=$(get_src_used_mb "$SRC")
        if [ "$SAVE_FREE_MB" -gt 0 ] && [ "$SRC_USED_MB" -gt 0 ]; then
            if [ "$SAVE_FREE_MB" -lt "$((SRC_USED_MB / 4))" ]; then
                if [ -n "$BEST_INT_DEV" ] && [ "$BEST_INT_FREE" -gt "$((SRC_USED_MB / 4))" ]; then
                    umount /home/partimag 2>/dev/null
                    SAVE_DEV="$BEST_INT_DEV"
                    mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV" 6 40; return; }
                    SAVE_FREE_MB=$BEST_INT_FREE
                else
                    local EST_GB=$((SRC_USED_MB * 40 / 100 / 1024))
                    local FREE_GB=$((SAVE_FREE_MB / 1024))
                    umount /home/partimag 2>/dev/null
                    dialog --msgbox "NOT ENOUGH SPACE!\n\nEstimated image: ~${EST_GB} GB\nStorage free: ~${FREE_GB} GB\n\nUse larger storage or LAN Server." 12 50
                    return
                fi
            fi
        fi
    fi

    # Image name
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1 | tr -d ' ')
    SRC_FRIENDLY=$(friendly_name "/dev/$SRC")
    SAVE_FREE_GB=$((${SAVE_FREE_MB:-0} / 1024))
    DEFAULT_NAME="Clone-$(date +%d%b)-${SRC_SIZE}"

    if [ "$SAVE_VIA_LAN" = "1" ]; then
        SAVE_DISPLAY="LAN Server ($LAN_SERVER_IP)"
    else
        SAVE_DISPLAY=$(friendly_name "$SAVE_DEV")
    fi

    IMG_NAME=$(dialog --title "Clone this PC" --inputbox \
        "Source: $SRC_FRIENDLY\nSave:   $SAVE_DISPLAY\nFree:   ~${SAVE_FREE_GB} GB\n\nImage name:" \
        12 60 "$DEFAULT_NAME" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }
    [ -z "$IMG_NAME" ] && IMG_NAME="$DEFAULT_NAME"

    # Note (optional)
    IMG_NOTE=$(dialog --title "Note (press OK to skip)" --inputbox \
        "Installed software:" 8 50 "" 3>&1 1>&2 2>&3)
    [ -n "$IMG_NOTE" ] && echo "$IMG_NOTE" > /home/partimag/.note_${IMG_NAME}

    # Overwrite check
    if [ -d "/home/partimag/$IMG_NAME" ]; then
        dialog --yesno "Image '$IMG_NAME' exists!\n\nOverwrite?" 8 40 || { umount /home/partimag 2>/dev/null; return; }
        rm -rf "/home/partimag/$IMG_NAME"
    fi

    # Auto compression based on space
    SRC_USED_MB=$(get_src_used_mb "$SRC")
    SAVE_FREE_MB=${SAVE_FREE_MB:-0}
    COMPRESS="-z3"  # Default: lz4
    if [ "$SAVE_FREE_MB" -gt 0 ] && [ "$SRC_USED_MB" -gt 0 ]; then
        local RATIO=$((SAVE_FREE_MB * 100 / SRC_USED_MB))
        if [ "$RATIO" -gt 150 ]; then
            COMPRESS="-z0"
        elif [ "$RATIO" -lt 80 ]; then
            COMPRESS="-z5p"
        fi
    fi

    # Confirm
    dialog --yesno "Start clone?\n\nFrom: $SRC_FRIENDLY\nTo:   $SAVE_DISPLAY\nName: $IMG_NAME\nNote: ${IMG_NOTE:-none}" 12 60
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }

    # Clone
    clear
    PART_COUNT=$(lsblk -l -o NAME /dev/$SRC 2>/dev/null | tail -n +2 | grep -v "^${SRC}$" | wc -l)
    echo ""
    echo "  ============================================"
    echo "    CLONING: $SRC_FRIENDLY"
    echo "    To: $SAVE_DISPLAY"
    echo "    Partitions: $PART_COUNT"
    echo "    DO NOT turn off or unplug!"
    echo "  ============================================"
    echo ""
    log "Clone /dev/$SRC -> $IMG_NAME ($PART_COUNT partitions)"

    /usr/sbin/ocs-sr -q2 -j2 -nogui -sc $COMPRESS -sfsck -senc -p true savedisk "$IMG_NAME" "$SRC" 2>&1 | tee -a "$LOG_FILE"
    OCS_RC=${PIPESTATUS[0]}

    if [ $OCS_RC -eq 0 ]; then
        SIZE=$(du -sh /home/partimag/$IMG_NAME 2>/dev/null | cut -f1)
        if verify_image "/home/partimag/$IMG_NAME"; then
            log "Clone OK: $IMG_NAME ($SIZE)"
            # Report to server
            MY_IP=$(ip -4 addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
            echo "$(date '+%H:%M:%S')|$MY_IP|CLONE|OK|$IMG_NAME|$SIZE" >> /home/partimag/.client_status 2>/dev/null
            dialog --msgbox "CLONE COMPLETE!\n\nImage: $IMG_NAME\nSize:  $SIZE\nSaved: $SAVE_DISPLAY" 10 55
        else
            log "Clone WARN: verification failed"
            dialog --msgbox "Clone finished but verification FAILED!\n\nImage may be incomplete.\nCheck log: $LOG_FILE" 10 50
        fi
    else
        log "Clone FAILED"
        LAST_ERR=$(tail -30 "$LOG_FILE" 2>/dev/null)
        dialog --title "CLONE FAILED" --msgbox "Clone failed!\n\nLast log:\n$LAST_ERR" 20 70
    fi

    umount /home/partimag 2>/dev/null
    do_shutdown
}

# ============================================
# INSTALL (Auto — detect everything)
# ============================================
do_install() {
    clear
    log "Starting install..."

    # Try LAN NFS first
    INSTALL_VIA_LAN=0
    if type lan_try_nfs_for_install >/dev/null 2>&1; then
        dialog --infobox "\n  Scanning LAN for server...\n  (waiting up to 10 seconds)" 6 45
        if lan_try_nfs_for_install; then
            INSTALL_VIA_LAN=1
        fi
    fi

    # If no LAN, find image on local storage
    if [ "$INSTALL_VIA_LAN" = "0" ]; then
        select_image || return
        mkdir -p /home/partimag
        mount $SEL_IMG_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount image device" 6 40; return; }
        IMG_NAME=$SEL_IMG_NAME
    else
        # Select image from LAN
        if type lan_select_nfs_image >/dev/null 2>&1; then
            lan_select_nfs_image || { umount /home/partimag 2>/dev/null; return; }
            IMG_NAME=$SEL_IMG_NAME
        else
            select_image || { umount /home/partimag 2>/dev/null; return; }
            IMG_NAME=$SEL_IMG_NAME
        fi
    fi

    # Auto-detect target: largest internal non-removable disk
    TGT=""
    TGT_SIZE_BYTES=0
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        [ "/dev/$dname" = "$BOOT_USB" ] && continue
        local IMG_BASE=$(echo "$SEL_IMG_DEV" | sed 's/[0-9]*$//;s/p[0-9]*$//' | sed 's|/dev/||')
        [ "$dname" = "$IMG_BASE" ] && continue
        local RM=$(lsblk -d -o RM /dev/$dname 2>/dev/null | tail -1 | tr -d ' ')
        [ "$RM" = "1" ] && continue
        local DSIZE=$(blockdev --getsize64 /dev/$dname 2>/dev/null)
        [ -z "$DSIZE" ] && continue
        if [ "$DSIZE" -gt "$TGT_SIZE_BYTES" ]; then
            TGT_SIZE_BYTES=$DSIZE
            TGT=$dname
        fi
    done

    [ -z "$TGT" ] && { dialog --msgbox "No target disk found!" 8 40; umount /home/partimag 2>/dev/null; return; }

    # Disk health check
    HEALTH=$(smartctl -H /dev/$TGT 2>/dev/null | grep -i "result" | awk '{print $NF}')
    if [ "$HEALTH" = "FAILED" ]; then
        dialog --yesno "WARNING: Disk health FAILING!\n\nContinue anyway?" 8 40 || { umount /home/partimag 2>/dev/null; return; }
    fi

    # Confirm
    TGT_FRIENDLY=$(friendly_name "/dev/$TGT")
    dialog --yesno "Install image to this PC?\n\nImage:  $IMG_NAME\nTarget: $TGT_FRIENDLY\n\n*** ALL DATA WILL BE ERASED! ***" 12 55
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }

    # Install
    clear
    PART_COUNT=0
    [ -f "/home/partimag/$IMG_NAME/parts" ] && PART_COUNT=$(wc -w < "/home/partimag/$IMG_NAME/parts")
    echo ""
    echo "  ============================================"
    echo "    INSTALLING: $IMG_NAME"
    echo "    Target: $TGT_FRIENDLY"
    echo "    Partitions: $PART_COUNT"
    echo "    DO NOT turn off or unplug!"
    echo "  ============================================"
    echo ""
    log "Install $IMG_NAME -> /dev/$TGT ($PART_COUNT partitions)"

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -nogui -j2 -sc -p true restoredisk "$IMG_NAME" "$TGT" 2>&1 | tee -a "$LOG_FILE"
    OCS_RC=${PIPESTATUS[0]}

    if [ $OCS_RC -eq 0 ]; then
        log "Install OK: $IMG_NAME -> /dev/$TGT"
        # Report to server
        MY_IP=$(ip -4 addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
        echo "$(date '+%H:%M:%S')|$MY_IP|INSTALL|OK|$IMG_NAME|$TGT" >> /home/partimag/.client_status 2>/dev/null
        dialog --msgbox "INSTALL COMPLETE!\n\nRemove USB and restart." 8 40
    else
        log "Install FAILED"
        MY_IP=$(ip -4 addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
        echo "$(date '+%H:%M:%S')|$MY_IP|INSTALL|FAILED|$IMG_NAME|$TGT" >> /home/partimag/.client_status 2>/dev/null
        LAST_ERR=$(tail -30 "$LOG_FILE" 2>/dev/null)
        dialog --title "INSTALL FAILED" --msgbox "Install failed!\n\nLast log:\n$LAST_ERR" 20 70
    fi

    umount /home/partimag 2>/dev/null
    do_shutdown
}

# ============================================
# MANAGE IMAGES (view + copy + delete)
# ============================================
do_manage() {
    while true; do
        ACTION=$(dialog --title "Manage Images" --menu "" 12 50 4 \
            1 "View all images" \
            2 "Copy image to another disk" \
            3 "Delete an image" \
            0 "Back" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return
        case $ACTION in
            1)
                INFO=""
                for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
                    [ -b "$dev" ] || continue
                    mkdir -p /tmp/_v 2>/dev/null
                    mount "$dev" /tmp/_v 2>/dev/null || continue
                    for dir in /tmp/_v/*/; do
                        if [ -f "${dir}disk" ] 2>/dev/null; then
                            local NAME=$(basename "$dir")
                            local SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                            local DATE=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1)
                            local NOTE=""; [ -f "/tmp/_v/.note_${NAME}" ] && NOTE=$(cat "/tmp/_v/.note_${NAME}")
                            local DEV_NAME=$(friendly_name "$dev")
                            INFO="${INFO}${NAME}  (${SIZE})  ${DATE}\n  ${DEV_NAME}\n  ${NOTE}\n\n"
                        fi
                    done
                    umount /tmp/_v 2>/dev/null
                done
                [ -z "$INFO" ] && INFO="No images found."
                dialog --title "All Images" --msgbox "$INFO" 20 65
                ;;
            2)
                select_image || continue
                local SRC_IMG_DEV=$SEL_IMG_DEV
                local SRC_IMG_NAME=$SEL_IMG_NAME

                mkdir -p /tmp/_csrc
                mount "$SRC_IMG_DEV" /tmp/_csrc 2>/dev/null || { dialog --msgbox "Cannot mount source" 6 40; continue; }
                local IMG_SIZE=$(du -sh "/tmp/_csrc/$SRC_IMG_NAME" 2>/dev/null | cut -f1)

                # Find destination: any writable partition that's not the source
                local DST_DEV="" DST_FREE=0
                for dev in /dev/sd*[0-9]* /dev/nvme*p[0-9]*; do
                    [ -b "$dev" ] || continue
                    [ "$ev" = "$SRC_IMG_DEV" ] && continue
                    local FS=$(blkid -o value -s TYPE "$dev" 2>/dev/null)
                    [ "$FS" = "iso9660" ] && continue
                    [ "$FS" = "squashfs" ] && continue
                    local PSIZE=$(($(blockdev --getsize64 "$dev" 2>/dev/null) / 1048576))
                    [ "$PSIZE" -lt 100 ] && continue
                    mkdir -p /tmp/_cdst
                    mount "$dev" /tmp/_cdst 2>/dev/null || continue
                    touch /tmp/_cdst/.writetest 2>/dev/null
                    if [ $? -eq 0 ]; then
                        rm -f /tmp/_cdst/.writetest
                        local FREE=$(df -m /tmp/_cdst 2>/dev/null | tail -1 | awk '{print $4}')
                        if [ "${FREE:-0}" -gt "$DST_FREE" ]; then
                            DST_FREE=$FREE
                            DST_DEV="$dev"
                        fi
                    fi
                    umount /tmp/_cdst 2>/dev/null
                done

                if [ -z "$DST_DEV" ] || [ "$DST_DEV" = "$SRC_IMG_DEV" ]; then
                    dialog --msgbox "No destination found!\n\nPlug in another USB or HDD." 8 45
                    umount /tmp/_csrc 2>/dev/null
                    continue
                fi

                local DST_FRIENDLY=$(friendly_name "$DST_DEV")
                local DST_FREE_GB=$((DST_FREE / 1024))
                dialog --yesno "Copy image?\n\nImage: $SRC_IMG_NAME ($IMG_SIZE)\nTo:    $DST_FRIENDLY\nFree:  ~${DST_FREE_GB} GB" 12 55
                if [ $? -ne 0 ]; then
                    umount /tmp/_csrc 2>/dev/null
                    continue
                fi

                mkdir -p /tmp/_cdst
                mount "$DST_DEV" /tmp/_cdst 2>/dev/null
                clear
                echo ""
                echo "  COPYING: $SRC_IMG_NAME ($IMG_SIZE)"
                echo "  To: $DST_FRIENDLY"
                echo "  DO NOT unplug!"
                echo ""
                [ -d "/tmp/_cdst/$SRC_IMG_NAME" ] && rm -rf "/tmp/_cdst/$SRC_IMG_NAME"
                cp -a "/tmp/_csrc/$SRC_IMG_NAME" "/tmp/_cdst/" 2>&1
                CP_RC=$?
                [ -f "/tmp/_csrc/.note_${SRC_IMG_NAME}" ] && cp "/tmp/_csrc/.note_${SRC_IMG_NAME}" "/tmp/_cdst/"
                umount /tmp/_cdst 2>/dev/null
                umount /tmp/_csrc 2>/dev/null

                if [ $CP_RC -eq 0 ]; then
                    dialog --msgbox "COPY COMPLETE!\n\n$SRC_IMG_NAME -> $DST_FRIENDLY" 8 55
                else
                    dialog --msgbox "COPY FAILED!\n\nDisk may be full." 8 40
                fi
                ;;
            3)
                select_image || continue
                dialog --yesno "DELETE: $SEL_IMG_NAME\n\nThis cannot be undone!" 8 40 || continue
                mkdir -p /tmp/_del
                mount "$SEL_IMG_DEV" /tmp/_del 2>/dev/null || { dialog --msgbox "Cannot mount" 6 30; continue; }
                rm -rf "/tmp/_del/$SEL_IMG_NAME"
                rm -f "/tmp/_del/.note_${SEL_IMG_NAME}"
                umount /tmp/_del 2>/dev/null
                dialog --msgbox "Deleted: $SEL_IMG_NAME" 6 40
                ;;
            0) return ;;
        esac
    done
}

# ============================================
# SPLASH
# ============================================
show_splash() {
    dialog --title "" --infobox "\n\n\
    ChumChim-Clonezilla v3.0\n\n\
    PC Clone & Deploy Tool\n\n\
    github.com/chumchim\n\n\
    Loading..." 12 45
    sleep 1
}

# ============================================
# PXE AUTO-INSTALL (client booted via PXE)
# ============================================
do_pxe_auto_install() {
    # Read server IP from kernel cmdline
    local server_ip=$(cat /proc/cmdline | tr ' ' '\n' | grep "chumchim_server=" | cut -d= -f2)
    [ -z "$server_ip" ] && return 1

    clear
    echo ""
    echo "  ============================================"
    echo "    ChumChim PXE Client — Auto Install"
    echo "    Server: $server_ip"
    echo "  ============================================"
    echo ""

    # Mount NFS image share
    echo "  [1/3] Connecting to server..."
    mkdir -p /home/partimag
    mount -t nfs -o rsize=65536,wsize=65536,nolock,vers=3 \
        "${server_ip}:/srv/chumchim" /home/partimag 2>/dev/null
    if [ $? -ne 0 ]; then
        mount -t nfs "${server_ip}:/srv/chumchim" /home/partimag 2>/dev/null
    fi
    if [ $? -ne 0 ]; then
        echo "  [X] Cannot connect to server NFS!"
        echo "  Falling back to menu..."
        sleep 3
        return 1
    fi
    echo "         Connected to $server_ip"

    # Find images
    echo "  [2/3] Finding images..."
    local img_count=0
    local img_name=""
    for dir in /home/partimag/*/; do
        if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
            img_count=$((img_count + 1))
            img_name=$(basename "$dir")
        fi
    done

    if [ $img_count -eq 0 ]; then
        echo "  [X] No images on server! Clone a PC first."
        umount /home/partimag 2>/dev/null
        sleep 3
        return 1
    fi

    # If multiple images, let user pick (or auto if just 1)
    if [ $img_count -gt 1 ]; then
        if type lan_select_nfs_image >/dev/null 2>&1; then
            lan_select_nfs_image || { umount /home/partimag 2>/dev/null; return 1; }
            img_name=$SEL_IMG_NAME
        fi
    fi
    echo "         Image: $img_name"

    # Find target disk (largest non-removable)
    echo "  [3/3] Finding target disk..."
    local tgt=""
    local tgt_size=0
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        local rm=$(lsblk -d -o RM /dev/$dname 2>/dev/null | tail -1 | tr -d ' ')
        [ "$rm" = "1" ] && continue
        local sz=$(blockdev --getsize64 /dev/$dname 2>/dev/null)
        [ -z "$sz" ] && continue
        if [ "$sz" -gt "$tgt_size" ]; then
            tgt_size=$sz
            tgt=$dname
        fi
    done

    if [ -z "$tgt" ]; then
        echo "  [X] No target disk found!"
        umount /home/partimag 2>/dev/null
        sleep 3
        return 1
    fi

    local tgt_gb=$((tgt_size / 1073741824))
    local tgt_model=$(lsblk -d -o MODEL /dev/$tgt 2>/dev/null | tail -1)
    echo "         Target: /dev/$tgt ($tgt_gb GB) $tgt_model"

    # Confirm (short timeout — auto-proceed if no input)
    echo ""
    echo "  *** INSTALLING $img_name -> /dev/$tgt ***"
    echo "  *** ALL DATA ON /dev/$tgt WILL BE ERASED ***"
    echo ""
    echo "  Starting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10

    # Install
    local part_count=0
    [ -f "/home/partimag/$img_name/parts" ] && part_count=$(wc -w < "/home/partimag/$img_name/parts")

    clear
    echo ""
    echo "  ============================================"
    echo "    PXE INSTALLING: $img_name"
    echo "    Target: /dev/$tgt ($tgt_gb GB)"
    echo "    Partitions: $part_count"
    echo "    DO NOT turn off!"
    echo "  ============================================"
    echo ""
    log "PXE Install $img_name -> /dev/$tgt ($part_count partitions)"

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -nogui -j2 -sc -p true restoredisk "$img_name" "$tgt" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}

    local my_ip=$(ip -4 addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ $rc -eq 0 ]; then
        log "PXE Install OK: $img_name -> /dev/$tgt"
        echo "$(date '+%H:%M:%S')|$my_ip|PXE-INST|OK|$img_name|$tgt" >> /home/partimag/.client_status 2>/dev/null
        echo ""
        echo "  ============================================"
        echo "    INSTALL COMPLETE!"
        echo "    Change BIOS back to 'Disk Boot'"
        echo "    Shutting down in 15 seconds..."
        echo "  ============================================"
        sleep 15
    else
        log "PXE Install FAILED: $img_name -> /dev/$tgt"
        echo "$(date '+%H:%M:%S')|$my_ip|PXE-INST|FAILED|$img_name|$tgt" >> /home/partimag/.client_status 2>/dev/null
        echo ""
        echo "  [X] INSTALL FAILED! Check server logs."
        sleep 30
    fi

    umount /home/partimag 2>/dev/null
    sync
    shutdown -h now 2>/dev/null || poweroff 2>/dev/null
    exit 0
}

# ============================================
# MAIN
# ============================================
find_boot_usb

# Check if booted via PXE (kernel cmdline has chumchim_pxe=1)
if grep -q "chumchim_pxe=1" /proc/cmdline 2>/dev/null; then
    do_pxe_auto_install
    # If auto-install fails, fall through to normal menu
fi

show_splash

while true; do
    choice=$(dialog --title "ChumChim-Clonezilla v3.0" \
        --menu "Select:" 13 50 5 \
        1 "Clone this PC" \
        2 "Install to PC" \
        3 "LAN Server" \
        4 "Manage Images" \
        0 "Shutdown" \
        3>&1 1>&2 2>&3)

    case $choice in
        1) do_clone ;;
        2) do_install ;;
        3) do_lan_server 2>/dev/null || dialog --msgbox "LAN Server not available.\n\nCheck: lan-server.sh" 8 40 ;;
        4) do_manage ;;
        0) do_shutdown ;;
        *) continue ;;
    esac
done
