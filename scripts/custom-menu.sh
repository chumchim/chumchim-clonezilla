#!/bin/bash
# ============================================
#   ChumChim-Clonezilla v2.0
# ============================================

# Load multicast module
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/multicast-server.sh" ] && source "$SCRIPT_DIR/multicast-server.sh"
[ -f "/usr/local/bin/multicast-server.sh" ] && source "/usr/local/bin/multicast-server.sh"

LOG_FILE="/tmp/chumchim.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> $LOG_FILE
    echo "  $1"
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
# Verify image integrity
# ============================================
verify_image() {
    IMG_DIR="$1"
    echo "  Verifying image..."
    if [ -f "$IMG_DIR/disk" ] && [ -f "$IMG_DIR/parts" ]; then
        PARTS=$(cat "$IMG_DIR/parts")
        ALL_OK=1
        for part in $PARTS; do
            FILES=$(ls "$IMG_DIR/" | grep "^${part}\." 2>/dev/null)
            if [ -z "$FILES" ]; then
                echo "  [X] Missing data for partition: $part"
                ALL_OK=0
            fi
        done
        if [ $ALL_OK -eq 1 ]; then
            echo "  [OK] Image verified"
            return 0
        fi
    else
        echo "  [X] Image incomplete (missing disk/parts file)"
    fi
    return 1
}

# ============================================
# Help
# ============================================
show_help() {
    clear
    echo ""
    echo "  ============================================"
    echo "    ChumChim-Clonezilla - Help"
    echo "  ============================================"
    echo ""
    echo "  [1] Clone Image this PC"
    echo "      Copy everything on this PC (Windows,"
    echo "      programs, files) into an image file."
    echo "      Save to USB HDD or flash drive."
    echo "      The PC is NOT changed."
    echo ""
    echo "  [2] Install Image to PC"
    echo "      Take an image file and install it"
    echo "      to this PC. WARNING: this will ERASE"
    echo "      everything on this PC and replace it"
    echo "      with the image."
    echo ""
    echo "  [3] Manage Images"
    echo "      View, rename, delete, or add notes"
    echo "      to your saved images."
    echo ""
    echo "  Typical workflow:"
    echo "    1. Install Windows + software on one PC"
    echo "    2. Clone it [1]"
    echo "    3. Install to other PCs [2]"
    echo "    4. Done! All PCs have same software."
    echo ""
    read -p "  Press Enter to go back..."
}

# ============================================
# Splash screen
# ============================================
show_splash() {
    clear
    echo ""
    echo ""
    echo ""
    echo "       ╔══════════════════════════════════╗"
    echo "       ║                                  ║"
    echo "       ║   ██████╗██╗  ██╗██╗   ██╗      ║"
    echo "       ║  ██╔════╝██║  ██║██║   ██║      ║"
    echo "       ║  ██║     ███████║██║   ██║      ║"
    echo "       ║  ██║     ██╔══██║██║   ██║      ║"
    echo "       ║  ╚██████╗██║  ██║╚██████╔╝      ║"
    echo "       ║   ╚═════╝╚═╝  ╚═╝ ╚═════╝       ║"
    echo "       ║                                  ║"
    echo "       ║   ChumChim-Clonezilla v2.0       ║"
    echo "       ║   PC Clone & Deploy Tool         ║"
    echo "       ║                                  ║"
    echo "       ║   Based on Clonezilla             ║"
    echo "       ║   github.com/chumchim             ║"
    echo "       ║                                  ║"
    echo "       ╚══════════════════════════════════╝"
    echo ""
    echo ""
    echo "       Loading..."
    sleep 3
}

# Find boot USB device (to exclude from target selection)
BOOT_USB=""
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

show_disks_safe() {
    # Show disks but mark boot USB
    echo ""
    echo "  Available disks:"
    echo "  -----------------------------------------------"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep "disk" | while read line; do
        DNAME=$(echo $line | awk '{print $1}')
        if [ "/dev/$DNAME" = "$BOOT_USB" ]; then
            echo "    $line  << USB BOOT (do not select!)"
        else
            echo "    $line"
        fi
    done
    echo "  -----------------------------------------------"
    echo ""
}

check_disk_exists() {
    if [ ! -b "/dev/$1" ]; then
        echo "  [X] Disk /dev/$1 not found!"
        return 1
    fi
    # Prevent selecting boot USB
    DNAME=$(echo "/dev/$1" | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
    if [ "$DNAME" = "$BOOT_USB" ]; then
        echo "  [X] That is the boot USB! Do not select it!"
        return 1
    fi
    return 0
}

check_disk_space() {
    # $1 = image dir, $2 = target disk
    if [ -d "$1" ]; then
        IMG_SIZE=$(du -s "$1" 2>/dev/null | awk '{print $1}')
        TGT_SIZE=$(lsblk -b -d -o SIZE /dev/$2 2>/dev/null | tail -1)
        TGT_SIZE_KB=$((TGT_SIZE / 1024))
        if [ $IMG_SIZE -gt $TGT_SIZE_KB ] 2>/dev/null; then
            echo "  [X] Target disk too small!"
            echo "      Image: $((IMG_SIZE / 1048576)) GB"
            echo "      Disk:  $((TGT_SIZE_KB / 1048576)) GB"
            return 1
        fi
    fi
    return 0
}

# ============================================
# Main Menu
# ============================================

show_menu() {
    find_boot_usb
    clear
    echo ""
    echo "  ============================================"
    echo "    ChumChim-Clonezilla v2.0"
    echo "  ============================================"
    echo ""
    echo "  [1] Clone this PC       Save PC as image"
    echo ""

    # Check if any image exists
    HAS_IMAGE=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_chk 2>/dev/null
        mount $dev /tmp/_chk 2>/dev/null
        for dir in /tmp/_chk/*/; do
            if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                HAS_IMAGE=1
                break 2
            fi
        done
        umount /tmp/_chk 2>/dev/null
    done

    if [ $HAS_IMAGE -eq 1 ]; then
        echo "  [2] Install to PC       Install image to PC"
    else
        echo "  [2] Install to PC       (no image yet)"
    fi

    echo ""
    echo ""
    echo "  [3] Deploy to many PCs  (Multicast via LAN)"
    echo "      1 USB + LAN = deploy 30 PCs in 30 min"
    echo ""
    echo "  [0] Shutdown"
    echo "  [?] More options"
    echo ""
    read -p "  Select: " choice
}

# ============================================
# Clone (Capture)
# ============================================

do_clone() {
    clear
    echo ""
    echo "  ============================================"
    echo "    CLONE IMAGE THIS PC"
    echo "  ============================================"
    echo "" > $LOG_FILE
    log "Starting clone..."

    # Auto-detect Windows disk
    detect_windows_disk
    show_disks_safe

    if [ -n "$WIN_DISK" ]; then
        echo "  >> Windows detected on: $WIN_DISK"
        echo ""
    fi

    read -p "  Source disk to clone [$WIN_DISK]: " SRC
    [ -z "$SRC" ] && SRC="$WIN_DISK"
    check_disk_exists "$SRC" || { read -p "  Press Enter..."; return; }

    # Source disk info
    SRC_SIZE=$(lsblk -d -o SIZE /dev/$SRC 2>/dev/null | tail -1)
    SRC_MODEL=$(lsblk -d -o MODEL /dev/$SRC 2>/dev/null | tail -1)
    echo "  Source: /dev/$SRC ($SRC_SIZE) $SRC_MODEL"

    echo ""
    echo "  Save image to which disk?"
    show_disks_safe
    read -p "  Save to disk (e.g. sdb): " SAVE
    check_disk_exists "$SAVE" || { read -p "  Press Enter..."; return; }
    read -p "  Partition number (e.g. 1): " PART

    SAVE_DEV="/dev/${SAVE}${PART}"
    mkdir -p /home/partimag
    mount $SAVE_DEV /home/partimag 2>/dev/null
    if [ $? -ne 0 ]; then
        SAVE_DEV="/dev/${SAVE}p${PART}"
        mount $SAVE_DEV /home/partimag 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "  [X] Cannot mount $SAVE_DEV"
            read -p "  Press Enter..."; return
        fi
    fi

    # Check free space on save location
    SAVE_FREE=$(df -BG /home/partimag 2>/dev/null | tail -1 | awk '{print $4}')
    echo "  Save disk free space: $SAVE_FREE"

    echo ""
    read -p "  Image name (e.g. Room101-IT): " IMG_NAME
    [ -z "$IMG_NAME" ] && IMG_NAME="Image-$(date +%Y%m%d-%H%M)"

    # Add note/description
    echo ""
    read -p "  Note (e.g. Win11 + Office + AutoCAD): " IMG_NOTE
    if [ -n "$IMG_NOTE" ]; then
        echo "$IMG_NOTE" > /home/partimag/.note_${IMG_NAME}
        echo "  Note saved."
    fi

    # Check if image already exists
    if [ -d "/home/partimag/$IMG_NAME" ]; then
        echo ""
        echo "  [!] Image '$IMG_NAME' already exists!"
        read -p "  Overwrite? (yes/no): " OW
        if [ "$OW" != "yes" ]; then
            umount /home/partimag 2>/dev/null
            echo "  Cancelled."
            read -p "  Press Enter..."; return
        fi
        rm -rf "/home/partimag/$IMG_NAME"
    fi

    echo ""
    echo "  ============================================"
    echo "    Source:  /dev/$SRC ($SRC_SIZE)"
    echo "    Save:    $SAVE_DEV/$IMG_NAME"
    echo "    Note:    ${IMG_NOTE:-none}"
    echo "  ============================================"
    echo ""
    echo ""
    echo "  Speed:"
    echo "  [1] Fast   (larger file, faster clone)"
    echo "  [2] Normal (balanced)"
    echo "  [3] Small  (smaller file, slower clone)"
    read -p "  Select (1/2/3): " SPEED
    case $SPEED in
        1) COMPRESS="-z0"; SPEED_TXT="Fast" ;;
        3) COMPRESS="-z5p"; SPEED_TXT="Small" ;;
        *) COMPRESS="-z1p"; SPEED_TXT="Normal" ;;
    esac

    echo ""
    read -p "  Start clone? (yes/no): " OK

    if [ "$OK" != "yes" ]; then
        umount /home/partimag 2>/dev/null
        echo "  Cancelled."
        read -p "  Press Enter..."; return
    fi

    log "Cloning /dev/$SRC to $IMG_NAME..."

    echo ""
    echo "  ============================================"
    echo "    CLONING... Please wait 10-30 minutes"
    echo "    DO NOT turn off or unplug USB!"
    echo "    Progress will show below"
    echo "  ============================================"
    echo ""

    /usr/sbin/ocs-sr -q2 -c -j2 $COMPRESS -i 16777216 -sfsck -senc -p true savedisk "$IMG_NAME" "$SRC" 2>&1 | tee -a $LOG_FILE

    if [ $? -eq 0 ]; then
        SIZE=$(du -sh /home/partimag/$IMG_NAME 2>/dev/null | cut -f1)
        log "Clone complete: $IMG_NAME ($SIZE)"

        # Verify image
        verify_image "/home/partimag/$IMG_NAME"

        echo ""
        echo "  ============================================"
        echo "    CLONE COMPLETE!"
        echo "    Image: $IMG_NAME ($SIZE)"
        echo "    Note:  ${IMG_NOTE:-none}"
        echo "  ============================================"
    else
        log "Clone FAILED"
        echo ""
        echo "  [X] Clone failed! Check log: $LOG_FILE"
    fi

    umount /home/partimag 2>/dev/null
    echo ""
    read -p "  [S]hutdown or [M]enu? (s/m): " AFTER
    [ "$AFTER" = "s" ] && poweroff
}

# ============================================
# Install (Deploy)
# ============================================

do_install() {
    clear
    echo ""
    echo "  ============================================"
    echo "    INSTALL IMAGE TO THIS PC"
    echo "  ============================================"
    echo "" > $LOG_FILE
    log "Starting install..."

    echo "  Scanning for images..."
    echo ""

    IMG_COUNT=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_img 2>/dev/null
        mount $dev /tmp/_img 2>/dev/null
        if [ -d "/tmp/_img" ]; then
            for dir in /tmp/_img/*/; do
                if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                    IMG_COUNT=$((IMG_COUNT + 1))
                    NAME=$(basename $dir)
                    SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    # Read note if exists
                    NOTE=""
                    if [ -f "/tmp/_img/.note_${NAME}" ]; then
                        NOTE=$(cat "/tmp/_img/.note_${NAME}")
                    fi
                    echo "  [$IMG_COUNT] $NAME  ($SIZE)"
                    [ -n "$NOTE" ] && echo "       $NOTE"

                    eval "IMG_DEV_$IMG_COUNT=$dev"
                    eval "IMG_NAME_$IMG_COUNT=$NAME"
                fi
            done
        fi
        umount /tmp/_img 2>/dev/null
    done

    if [ $IMG_COUNT -eq 0 ]; then
        echo "  No images found!"
        echo "  Plug in USB/HDD with images first."
        read -p "  Press Enter..."; return
    fi

    echo ""
    read -p "  Select image number: " SEL

    if [ -z "$SEL" ] || [ "$SEL" -lt 1 ] || [ "$SEL" -gt $IMG_COUNT ] 2>/dev/null; then
        echo "  Cancelled."
        read -p "  Press Enter..."; return
    fi

    eval "IMG_DEV=\$IMG_DEV_$SEL"
    eval "IMG_NAME=\$IMG_NAME_$SEL"

    mkdir -p /home/partimag
    mount $IMG_DEV /home/partimag 2>/dev/null

    echo ""
    echo "  Selected: $IMG_NAME"

    # Select target
    echo ""
    echo "  Target disk (will be ERASED!):"
    show_disks_safe

    read -p "  Target disk (e.g. sda): " TGT

    check_disk_exists "$TGT" || {
        umount /home/partimag 2>/dev/null
        read -p "  Press Enter..."; return
    }

    # Check disk health (basic)
    HEALTH=$(smartctl -H /dev/$TGT 2>/dev/null | grep -i "result" | awk '{print $NF}')
    if [ "$HEALTH" = "FAILED" ]; then
        echo ""
        echo "  [!] WARNING: Disk /dev/$TGT health is FAILING!"
        echo "  [!] This disk may be dying. Continue at your own risk."
        read -p "  Continue anyway? (yes/no): " HCON
        [ "$HCON" != "yes" ] && { umount /home/partimag 2>/dev/null; return; }
    fi

    # Disk info
    TGT_SIZE=$(lsblk -d -o SIZE /dev/$TGT 2>/dev/null | tail -1)
    TGT_MODEL=$(lsblk -d -o MODEL /dev/$TGT 2>/dev/null | tail -1)

    echo ""
    echo "  ============================================"
    echo "    Image:   $IMG_NAME"
    echo "    Target:  /dev/$TGT ($TGT_SIZE) $TGT_MODEL"
    echo ""
    echo "    !! ALL DATA ON /dev/$TGT WILL BE ERASED !!"
    echo "  ============================================"
    echo ""
    read -p "  Type 'install' to confirm: " OK

    if [ "$OK" != "install" ]; then
        umount /home/partimag 2>/dev/null
        echo "  Cancelled."
        read -p "  Press Enter..."; return
    fi

    log "Installing $IMG_NAME to /dev/$TGT..."

    echo ""
    echo "  ============================================"
    echo "    INSTALLING... Please wait 10-30 minutes"
    echo "    DO NOT turn off or unplug USB!"
    echo "    Progress will show below"
    echo "  ============================================"
    echo ""

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -j2 -c -p true restoredisk "$IMG_NAME" "$TGT" 2>&1 | tee -a $LOG_FILE

    if [ $? -eq 0 ]; then
        log "Install complete: $IMG_NAME -> /dev/$TGT"
        echo ""
        echo "  ============================================"
        echo "    INSTALL COMPLETE!"
        echo "    Remove USB and restart."
        echo "  ============================================"
    else
        log "Install FAILED"
        echo ""
        echo "  [X] Install failed! Check log: $LOG_FILE"
    fi

    umount /home/partimag 2>/dev/null
    echo ""
    read -p "  [S]hutdown or [M]enu? (s/m): " AFTER
    [ "$AFTER" = "s" ] && poweroff
}

# ============================================
# Manage Images
# ============================================

do_manage() {
    clear
    echo ""
    echo "  ============================================"
    echo "    MANAGE IMAGES"
    echo "  ============================================"
    echo ""
    echo "  Scanning..."
    echo ""

    IMG_COUNT=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_mgr 2>/dev/null
        mount $dev /tmp/_mgr 2>/dev/null
        if [ -d "/tmp/_mgr" ]; then
            for dir in /tmp/_mgr/*/; do
                if [ -f "${dir}disk" ] 2>/dev/null || [ -f "${dir}parts" ] 2>/dev/null; then
                    IMG_COUNT=$((IMG_COUNT + 1))
                    NAME=$(basename $dir)
                    SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    DATE=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1)
                    NOTE=""
                    [ -f "/tmp/_mgr/.note_${NAME}" ] && NOTE=$(cat "/tmp/_mgr/.note_${NAME}")

                    echo "  [$IMG_COUNT] $NAME"
                    echo "       Size: $SIZE  Date: $DATE"
                    [ -n "$NOTE" ] && echo "       Note: $NOTE"
                    echo ""

                    eval "MGR_DEV_$IMG_COUNT=$dev"
                    eval "MGR_NAME_$IMG_COUNT=$NAME"
                    eval "MGR_DIR_$IMG_COUNT=$dir"
                fi
            done
        fi
        umount /tmp/_mgr 2>/dev/null
    done

    if [ $IMG_COUNT -eq 0 ]; then
        echo "  No images found."
        read -p "  Press Enter..."; return
    fi

    echo "  ============================================"
    echo "  [D] Delete an image"
    echo "  [R] Rename an image"
    echo "  [N] Add/edit note"
    echo "  [V] Verify an image"
    echo "  [B] Back to menu"
    echo ""
    read -p "  Select: " ACT

    case $ACT in
        d|D)
            read -p "  Delete which image number? " DNUM
            eval "DNAME=\$MGR_NAME_$DNUM"
            eval "DDEV=\$MGR_DEV_$DNUM"
            if [ -z "$DNAME" ]; then echo "  Invalid."; read -p "  Press Enter..."; return; fi
            echo ""
            echo "  Delete '$DNAME'?"
            read -p "  Type 'delete' to confirm: " DCONF
            if [ "$DCONF" = "delete" ]; then
                mount $DDEV /tmp/_mgr 2>/dev/null
                rm -rf "/tmp/_mgr/$DNAME"
                rm -f "/tmp/_mgr/.note_${DNAME}"
                umount /tmp/_mgr 2>/dev/null
                echo "  [OK] Deleted: $DNAME"
            else
                echo "  Cancelled."
            fi
            ;;
        r|R)
            read -p "  Rename which image number? " RNUM
            eval "RNAME=\$MGR_NAME_$RNUM"
            eval "RDEV=\$MGR_DEV_$RNUM"
            if [ -z "$RNAME" ]; then echo "  Invalid."; read -p "  Press Enter..."; return; fi
            read -p "  New name: " NEWNAME
            if [ -n "$NEWNAME" ]; then
                mount $RDEV /tmp/_mgr 2>/dev/null
                mv "/tmp/_mgr/$RNAME" "/tmp/_mgr/$NEWNAME"
                # Rename note too
                [ -f "/tmp/_mgr/.note_${RNAME}" ] && mv "/tmp/_mgr/.note_${RNAME}" "/tmp/_mgr/.note_${NEWNAME}"
                umount /tmp/_mgr 2>/dev/null
                echo "  [OK] Renamed: $RNAME -> $NEWNAME"
            else
                echo "  Cancelled."
            fi
            ;;
        v|V)
            read -p "  Verify which image number? " VNUM
            eval "VNAME=\$MGR_NAME_$VNUM"
            eval "VDEV=\$MGR_DEV_$VNUM"
            if [ -z "$VNAME" ]; then echo "  Invalid."; read -p "  Press Enter..."; return; fi
            mount $VDEV /tmp/_mgr 2>/dev/null
            verify_image "/tmp/_mgr/$VNAME"
            umount /tmp/_mgr 2>/dev/null
            ;;
        n|N)
            read -p "  Add note to which image number? " NNUM
            eval "NNAME=\$MGR_NAME_$NNUM"
            eval "NDEV=\$MGR_DEV_$NNUM"
            if [ -z "$NNAME" ]; then echo "  Invalid."; read -p "  Press Enter..."; return; fi
            read -p "  Note: " NNOTE
            mount $NDEV /tmp/_mgr 2>/dev/null
            echo "$NNOTE" > "/tmp/_mgr/.note_${NNAME}"
            umount /tmp/_mgr 2>/dev/null
            echo "  [OK] Note saved for $NNAME"
            ;;
    esac
    read -p "  Press Enter..."
}

# ============================================
# Main Loop
# ============================================

# Show splash on first boot
show_splash

while true; do
    show_menu
    case $choice in
        1) do_clone ;;
        3) do_multicast 2>/dev/null || { echo "  Multicast not available"; read -p "  Press Enter..."; } ;;
        2)
            if [ $HAS_IMAGE -eq 0 ]; then
                echo ""
                echo "  No image found. Clone a PC first [1]"
                read -p "  Press Enter..."
            else
                do_install
            fi
            ;;
        "?"|h|H)
            clear
            echo ""
            echo "  ============================================"
            echo "    More Options"
            echo "  ============================================"
            echo ""
            echo "  [3] Manage Images  (view, rename, delete)"
            echo "  [4] Help"
            echo "  [9] Command line"
            echo "  [0] Back"
            echo ""
            read -p "  Select: " sub
            case $sub in
                3) do_manage ;;
                4) show_help ;;
                9) echo "  Type 'exit' to return"; /bin/bash ;;
                *) ;;
            esac
            ;;
        3) do_manage ;;
        9)
            echo "  Type 'exit' to return to menu"
            /bin/bash
            ;;
        0)
            echo "  Shutting down..."
            poweroff
            ;;
        *)
            echo "  Invalid choice"
            sleep 1
            ;;
    esac
done
