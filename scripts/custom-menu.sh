#!/bin/bash
# ============================================
#   ChumChim-Clonezilla v2.0
#   Full dialog UI
# ============================================

# Load multicast module
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/multicast-server.sh" ] && source "$SCRIPT_DIR/multicast-server.sh"
[ -f "/usr/local/bin/multicast-server.sh" ] && source "/usr/local/bin/multicast-server.sh"

LOG_FILE="/tmp/chumchim.log"
BOOT_USB=""

log() { echo "[$(date '+%H:%M:%S')] $1" >> $LOG_FILE; }

# ============================================
# Find boot USB (to exclude from selection)
# ============================================
find_boot_usb() {
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
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
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
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
    SEL_DISK=""
    OPTS=""
    for dname in $(lsblk -d -o NAME,TYPE | grep "disk" | awk '{print $1}'); do
        [ "/dev/$dname" = "$BOOT_USB" ] && continue
        DSIZE=$(lsblk -d -o SIZE /dev/$dname 2>/dev/null | tail -1)
        DMODEL=$(lsblk -d -o MODEL /dev/$dname 2>/dev/null | tail -1)
        OPTS="$OPTS $dname \"$DSIZE  $DMODEL\""
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
    OPTS=""; IMG_COUNT=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_sel 2>/dev/null
        mount $dev /tmp/_sel 2>/dev/null
        for dir in /tmp/_sel/*/; do
            if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                IMG_COUNT=$((IMG_COUNT + 1))
                NAME=$(basename $dir)
                SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                NOTE=""; [ -f "/tmp/_sel/.note_${NAME}" ] && NOTE=" - $(cat /tmp/_sel/.note_${NAME})"
                OPTS="$OPTS $IMG_COUNT \"$NAME ($SIZE)$NOTE\""
                eval "SSEL_DEV_$IMG_COUNT=$dev"
                eval "SSEL_NAME_$IMG_COUNT=$NAME"
            fi
        done
        umount /tmp/_sel 2>/dev/null
    done
    [ $IMG_COUNT -eq 0 ] && { dialog --msgbox "No images found!\n\nClone a PC first." 8 40; return 1; }
    RESULT=$(eval "dialog --title \"Select Image\" --menu \"\" 15 70 6 $OPTS" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    eval "SEL_IMG_DEV=\$SSEL_DEV_$RESULT"
    eval "SEL_IMG_NAME=\$SSEL_NAME_$RESULT"
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
# CLONE
# ============================================
do_clone() {
    clear
    log "Starting clone..."
    detect_windows_disk

    # Select source
    select_disk "Clone: Select SOURCE disk" || return
    SRC=$SEL_DISK

    # Select save disk + partition
    select_disk "Clone: Select SAVE disk" || return
    SAVE=$SEL_DISK
    select_partition "$SAVE" || return

    SAVE_DEV="/dev/$SEL_PART"
    mkdir -p /home/partimag
    mount $SAVE_DEV /home/partimag 2>/dev/null || { dialog --msgbox "Cannot mount $SAVE_DEV" 6 40; return; }

    # Image name
    IMG_NAME=$(dialog --title "Image Name" --inputbox "Name for this image:" 8 50 "Room$(date +%m%d)" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }
    [ -z "$IMG_NAME" ] && IMG_NAME="Image-$(date +%Y%m%d-%H%M)"

    # Note
    IMG_NOTE=$(dialog --title "Image Note (optional)" --inputbox "Describe what software is installed:" 8 60 "" 3>&1 1>&2 2>&3)
    [ -n "$IMG_NOTE" ] && echo "$IMG_NOTE" > /home/partimag/.note_${IMG_NAME}

    # Check existing
    if [ -d "/home/partimag/$IMG_NAME" ]; then
        dialog --yesno "Image '$IMG_NAME' exists!\n\nOverwrite?" 8 40 || { umount /home/partimag 2>/dev/null; return; }
        rm -rf "/home/partimag/$IMG_NAME"
    fi

    # Speed
    SPEED=$(dialog --title "Clone Speed" --menu "" 10 50 3 \
        1 "Fast    (larger file, faster)" \
        2 "Normal  (balanced)" \
        3 "Small   (smaller file, slower)" \
        3>&1 1>&2 2>&3)
    case $SPEED in
        1) COMPRESS="-z0" ;;
        3) COMPRESS="-z5p" ;;
        *) COMPRESS="-z1p" ;;
    esac

    # Confirm
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1)
    dialog --yesno "Start clone?\n\nSource: /dev/$SRC ($SRC_SIZE)\nSave:   $SAVE_DEV/$IMG_NAME\nNote:   ${IMG_NOTE:-none}" 12 50
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }

    # Clone
    clear
    echo ""
    echo "  ============================================"
    echo "    CLONING: /dev/$SRC -> $IMG_NAME"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""
    log "Clone /dev/$SRC -> $IMG_NAME"

    /usr/sbin/ocs-sr -q2 -c -j2 $COMPRESS -i 16777216 -sfsck -senc -p true savedisk "$IMG_NAME" "$SRC" 2>&1 | tee -a $LOG_FILE

    if [ $? -eq 0 ]; then
        verify_image "/home/partimag/$IMG_NAME"
        SIZE=$(du -sh /home/partimag/$IMG_NAME 2>/dev/null | cut -f1)
        log "Clone OK: $IMG_NAME ($SIZE)"
        dialog --msgbox "CLONE COMPLETE!\n\nImage: $IMG_NAME ($SIZE)\nNote: ${IMG_NOTE:-none}" 10 50
    else
        log "Clone FAILED"
        dialog --msgbox "CLONE FAILED!\n\nCheck log: $LOG_FILE" 8 40
    fi

    umount /home/partimag 2>/dev/null

    dialog --yesno "Shutdown computer?" 6 30 && poweroff
}

# ============================================
# INSTALL
# ============================================
do_install() {
    clear
    log "Starting install..."

    # Select image
    select_image || return

    mkdir -p /home/partimag
    mount $SEL_IMG_DEV /home/partimag 2>/dev/null
    IMG_NAME=$SEL_IMG_NAME

    # Select target
    select_disk "Install: Select TARGET disk (ERASED!)" || { umount /home/partimag 2>/dev/null; return; }
    TGT=$SEL_DISK

    # Disk health
    HEALTH=$(smartctl -H /dev/$TGT 2>/dev/null | grep -i "result" | awk '{print $NF}')
    [ "$HEALTH" = "FAILED" ] && dialog --yesno "WARNING: Disk health FAILING!\n\nContinue anyway?" 8 40 || { umount /home/partimag 2>/dev/null; return; }

    # Confirm
    TGT_SIZE=$(lsblk -d -o SIZE /dev/$TGT 2>/dev/null | tail -1)
    TGT_MODEL=$(lsblk -d -o MODEL /dev/$TGT 2>/dev/null | tail -1)
    dialog --yesno "Install image to this disk?\n\nImage:  $IMG_NAME\nTarget: /dev/$TGT ($TGT_SIZE)\nModel:  $TGT_MODEL\n\nALL DATA WILL BE ERASED!" 14 50
    [ $? -ne 0 ] && { umount /home/partimag 2>/dev/null; return; }

    # Install
    clear
    echo ""
    echo "  ============================================"
    echo "    INSTALLING: $IMG_NAME -> /dev/$TGT"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""
    log "Install $IMG_NAME -> /dev/$TGT"

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -j2 -c -p true restoredisk "$IMG_NAME" "$TGT" 2>&1 | tee -a $LOG_FILE

    if [ $? -eq 0 ]; then
        log "Install OK: $IMG_NAME -> /dev/$TGT"
        dialog --msgbox "INSTALL COMPLETE!\n\nRemove USB and restart." 8 40
    else
        log "Install FAILED"
        dialog --msgbox "INSTALL FAILED!\n\nCheck log: $LOG_FILE" 8 40
    fi

    umount /home/partimag 2>/dev/null

    dialog --yesno "Shutdown computer?" 6 30 && poweroff
}

# ============================================
# MANAGE IMAGES
# ============================================
do_manage() {
    while true; do
        ACTION=$(dialog --title "Manage Images" --menu "" 12 50 4 \
            1 "View all images" \
            2 "Delete an image" \
            3 "Add/edit note" \
            0 "Back" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return
        case $ACTION in
            1)
                INFO=""
                for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
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
                dialog --title "All Images" --msgbox "$INFO" 20 60
                ;;
            2)
                select_image || continue
                dialog --yesno "DELETE image:\n$SEL_IMG_NAME\n\nThis cannot be undone!" 10 40 || continue
                mount $SEL_IMG_DEV /tmp/_del 2>/dev/null
                rm -rf "/tmp/_del/$SEL_IMG_NAME"
                rm -f "/tmp/_del/.note_${SEL_IMG_NAME}"
                umount /tmp/_del 2>/dev/null
                dialog --msgbox "Deleted: $SEL_IMG_NAME" 6 40
                ;;
            3)
                select_image || continue
                NOTE=$(dialog --title "Note for $SEL_IMG_NAME" --inputbox "" 8 60 "" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                mount $SEL_IMG_DEV /tmp/_note 2>/dev/null
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
ChumChim-Clonezilla v2.0\n\n\
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
    ChumChim-Clonezilla v2.0\n\n\
    PC Clone & Deploy Tool\n\n\
    Based on Clonezilla\n\
    github.com/chumchim\n\n\
    Loading..." 14 45
    sleep 3
}

# ============================================
# MAIN
# ============================================
find_boot_usb
show_splash

while true; do
    choice=$(dialog --title "ChumChim-Clonezilla v2.0" \
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
        0) dialog --yesno "Shutdown?" 6 30 && poweroff ;;
        *) break ;;
    esac
done
