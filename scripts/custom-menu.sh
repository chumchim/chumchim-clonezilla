#!/bin/bash
# ============================================
#   School Clonezilla - Custom Menu
# ============================================

show_menu() {
    clear
    echo ""
    echo "  ============================================"
    echo "    ChumChim-Clonezilla v1.0"
    echo "  ============================================"
    echo ""
    echo "  [1] Clone Image this PC   (save PC as image file)"
    echo ""

    # Check if any image exists on any drive
    HAS_IMAGE=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_chk 2>/dev/null
        mount $dev /tmp/_chk 2>/dev/null
        if [ -d "/tmp/_chk" ]; then
            for dir in /tmp/_chk/*/; do
                if [ -f "${dir}disk" ] || [ -f "${dir}parts" ]; then
                    HAS_IMAGE=1
                    break 2
                fi
            done
        fi
        umount /tmp/_chk 2>/dev/null
    done

    if [ $HAS_IMAGE -eq 1 ]; then
        echo "  [2] Install Image to PC   (install image to this PC)"
    else
        echo "  [2] Install Image to PC   (no image found)"
    fi

    echo ""
    echo "  [9] Command line"
    echo "  [0] Shutdown"
    echo ""
    read -p "  Select: " choice
}

find_usb() {
    # Find the USB we booted from (has /live folder)
    USB_DEV=""
    USB_MNT=""
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_find 2>/dev/null
        mount $dev /tmp/_find 2>/dev/null
        if [ -d "/tmp/_find/live" ]; then
            USB_DEV=$dev
            USB_MNT="/tmp/_find"
            return 0
        fi
        umount /tmp/_find 2>/dev/null
    done
    return 1
}

show_disks() {
    echo ""
    echo "  Available disks:"
    echo "  -----------------------------------------------"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep "disk" | while read line; do
        echo "    $line"
    done
    echo "  -----------------------------------------------"
    echo ""
}

do_capture() {
    clear
    echo ""
    echo "  ============================================"
    echo "    CLONE THIS PC"
    echo "  ============================================"
    echo ""

    # Show disks
    show_disks

    # Select source
    read -p "  Source disk to capture (e.g. sda nvme0n1): " SRC

    if [ -z "$SRC" ]; then
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Check source exists
    if [ ! -b "/dev/$SRC" ]; then
        echo "  [X] /dev/$SRC not found!"
        read -p "  Press Enter..."
        return
    fi

    # Select save location
    echo ""
    echo "  Save image to:"
    show_disks
    read -p "  Save to disk (e.g. sdb): " SAVE
    read -p "  Partition number (e.g. 1): " PART

    if [ -z "$SAVE" ] || [ -z "$PART" ]; then
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Mount save location
    SAVE_DEV="/dev/${SAVE}${PART}"
    mkdir -p /home/partimag
    mount $SAVE_DEV /home/partimag 2>/dev/null
    if [ $? -ne 0 ]; then
        # Try nvme format
        SAVE_DEV="/dev/${SAVE}p${PART}"
        mount $SAVE_DEV /home/partimag 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "  [X] Cannot mount $SAVE_DEV"
            read -p "  Press Enter..."
            return
        fi
    fi

    # Image name
    echo ""
    read -p "  Image name (e.g. Room101): " IMG_NAME
    if [ -z "$IMG_NAME" ]; then
        IMG_NAME="MyImage-$(date +%Y%m%d)"
    fi

    # Confirm
    echo ""
    echo "  ============================================"
    echo "    Source:  /dev/$SRC"
    echo "    Save:    $SAVE_DEV -> /home/partimag/$IMG_NAME"
    echo "  ============================================"
    echo ""
    read -p "  Start capture? (yes/no): " OK

    if [ "$OK" != "yes" ]; then
        umount /home/partimag 2>/dev/null
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Run Clonezilla capture
    echo ""
    echo "  ============================================"
    echo "    CLONING... Please wait 10-30 minutes"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""

    /usr/sbin/ocs-sr -q2 -c -j2 -z5p -i 4096 -sfsck -senc -p true savedisk "$IMG_NAME" "$SRC"

    if [ $? -eq 0 ]; then
        SIZE=$(du -sh /home/partimag/$IMG_NAME 2>/dev/null | cut -f1)
        echo ""
        echo "  ============================================"
        echo "    CLONE COMPLETE!"
        echo "    Image: $IMG_NAME ($SIZE)"
        echo "  ============================================"
    else
        echo ""
        echo "  [X] Capture failed!"
    fi

    umount /home/partimag 2>/dev/null
    echo ""
    read -p "  Press Enter..."
}

do_deploy() {
    clear
    echo ""
    echo "  ============================================"
    echo "    INSTALL IMAGE TO THIS PC"
    echo "  ============================================"
    echo ""

    # Find image
    echo "  Looking for images..."
    FOUND=0
    for dev in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
        mkdir -p /tmp/_img 2>/dev/null
        mount $dev /tmp/_img 2>/dev/null
        if [ -d "/tmp/_img" ]; then
            for dir in /tmp/_img/*/; do
                if [ -f "$dir/disk" ] || [ -f "$dir/parts" ]; then
                    IMG=$(basename $dir)
                    echo "    [$dev] $IMG"
                    FOUND=1
                fi
            done
        fi
        umount /tmp/_img 2>/dev/null
    done

    if [ $FOUND -eq 0 ]; then
        echo "  No images found!"
        echo "  Make sure USB with images is plugged in."
        read -p "  Press Enter..."
        return
    fi

    echo ""
    read -p "  Image source disk (e.g. sdb): " IMG_DISK
    read -p "  Partition number (e.g. 1): " IMG_PART
    read -p "  Image name: " IMG_NAME

    if [ -z "$IMG_DISK" ] || [ -z "$IMG_NAME" ]; then
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Mount image source
    IMG_DEV="/dev/${IMG_DISK}${IMG_PART}"
    mkdir -p /home/partimag
    mount $IMG_DEV /home/partimag 2>/dev/null || mount "/dev/${IMG_DISK}p${IMG_PART}" /home/partimag 2>/dev/null

    if [ ! -d "/home/partimag/$IMG_NAME" ]; then
        echo "  [X] Image not found: $IMG_NAME"
        umount /home/partimag 2>/dev/null
        read -p "  Press Enter..."
        return
    fi

    # Select target
    echo ""
    echo "  Target disk (will be ERASED!):"
    show_disks
    read -p "  Target disk (e.g. sda nvme0n1): " TGT

    if [ -z "$TGT" ]; then
        umount /home/partimag 2>/dev/null
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Confirm
    echo ""
    echo "  ============================================"
    echo "    Image:   $IMG_NAME"
    echo "    Target:  /dev/$TGT"
    echo ""
    echo "    WARNING: /dev/$TGT will be ERASED!"
    echo "  ============================================"
    echo ""
    read -p "  Install? (yes/no): " OK

    if [ "$OK" != "yes" ]; then
        umount /home/partimag 2>/dev/null
        echo "  Cancelled."
        read -p "  Press Enter..."
        return
    fi

    # Run Clonezilla restore
    echo ""
    echo "  ============================================"
    echo "    INSTALLING... Please wait 10-30 minutes"
    echo "    DO NOT turn off or unplug USB!"
    echo "  ============================================"
    echo ""

    /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -j2 -c -p true restoredisk "$IMG_NAME" "$TGT"

    if [ $? -eq 0 ]; then
        echo ""
        echo "  ============================================"
        echo "    INSTALL COMPLETE!"
        echo "    Remove USB and restart."
        echo "  ============================================"
    else
        echo ""
        echo "  [X] Install failed!"
    fi

    umount /home/partimag 2>/dev/null
    echo ""
    read -p "  Press Enter..."
}

# ============================================
# Main loop
# ============================================

while true; do
    show_menu
    case $choice in
        1) do_capture ;;
        2)
            if [ $HAS_IMAGE -eq 0 ]; then
                echo ""
                echo "  No image found. Clone a PC first [1]"
                read -p "  Press Enter..."
            else
                do_deploy
            fi
            ;;
        9)
            echo ""
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
