#!/bin/bash
# ============================================
#   School Clonezilla - Custom Menu
#   Boot แล้วเห็นเมนูนี้เลย
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

clear
echo ""
echo -e "${CYAN}  ============================================${NC}"
echo -e "${CYAN}    School Image Builder                      ${NC}"
echo -e "${CYAN}  ============================================${NC}"
echo ""
echo -e "${WHITE}  [1] Capture this PC   (save as image)${NC}"
echo -e "${WHITE}  [2] Deploy image      (install to this PC)${NC}"
echo -e "${WHITE}  [3] Command line${NC}"
echo ""
read -p "  Select (1, 2, or 3): " choice

case $choice in
    1)
        echo ""
        echo -e "${CYAN}  CAPTURE THIS PC${NC}"
        echo -e "${CYAN}  ===============${NC}"
        echo ""

        # Find Windows partition
        WIN_PART=""
        for part in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
            if [ -d "$(mount_point $part 2>/dev/null)/Windows" ] 2>/dev/null; then
                WIN_PART=$part
                break
            fi
        done

        # Find source disk
        echo "  Available disks:"
        lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|sr"
        echo ""
        read -p "  Source disk (e.g. sda): " SRC_DISK

        # Find save location
        echo ""
        echo "  Save to:"
        lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|sr\|$SRC_DISK"
        echo ""
        read -p "  Save to disk (e.g. sdb): " SAVE_DISK
        read -p "  Image name (e.g. Room101): " IMG_NAME

        if [ -z "$IMG_NAME" ]; then
            IMG_NAME="MyImage"
        fi

        echo ""
        echo -e "${YELLOW}  Source: /dev/$SRC_DISK${NC}"
        echo -e "${YELLOW}  Save:  /dev/$SAVE_DISK/$IMG_NAME${NC}"
        echo ""
        read -p "  Start capture? (yes/no): " confirm

        if [ "$confirm" = "yes" ]; then
            echo ""
            echo -e "${CYAN}  ============================================${NC}"
            echo -e "${CYAN}    CAPTURING... Please wait 10-30 minutes    ${NC}"
            echo -e "${CYAN}    DO NOT turn off or unplug USB!            ${NC}"
            echo -e "${CYAN}  ============================================${NC}"
            echo ""

            # Mount save disk
            mkdir -p /mnt/save
            mount /dev/${SAVE_DISK}1 /mnt/save 2>/dev/null || mount /dev/$SAVE_DISK /mnt/save

            # Run Clonezilla savedisk
            /usr/sbin/ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -senc -p poweroff savedisk "$IMG_NAME" "$SRC_DISK"

            echo ""
            echo -e "${GREEN}  ============================================${NC}"
            echo -e "${GREEN}    CAPTURE COMPLETE!                         ${NC}"
            echo -e "${GREEN}  ============================================${NC}"
            echo ""
        fi
        ;;

    2)
        echo ""
        echo -e "${CYAN}  DEPLOY IMAGE${NC}"
        echo -e "${CYAN}  ============${NC}"
        echo ""

        # Find image
        echo "  Looking for images..."
        for disk in /dev/sd*[0-9] /dev/nvme*p[0-9]; do
            mkdir -p /mnt/check
            mount $disk /mnt/check 2>/dev/null
            if [ -d "/mnt/check/home/partimag" ]; then
                echo "  Found images on $disk:"
                ls /mnt/check/home/partimag/ 2>/dev/null
            fi
            umount /mnt/check 2>/dev/null
        done

        echo ""
        read -p "  Image name to deploy: " IMG_NAME

        # Find target disk
        echo ""
        echo "  Available disks:"
        lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|sr"
        echo ""
        echo -e "${RED}  WARNING: Target disk will be ERASED!${NC}"
        read -p "  Target disk (e.g. sda): " TGT_DISK
        read -p "  Confirm deploy to /dev/$TGT_DISK? (yes/no): " confirm

        if [ "$confirm" = "yes" ]; then
            echo ""
            echo -e "${CYAN}  ============================================${NC}"
            echo -e "${CYAN}    DEPLOYING... Please wait 10-30 minutes    ${NC}"
            echo -e "${CYAN}    DO NOT turn off or unplug USB!            ${NC}"
            echo -e "${CYAN}  ============================================${NC}"
            echo ""

            # Run Clonezilla restoredisk
            /usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -j2 -c -p poweroff restoredisk "$IMG_NAME" "$TGT_DISK"

            echo ""
            echo -e "${GREEN}  ============================================${NC}"
            echo -e "${GREEN}    DEPLOY COMPLETE!                          ${NC}"
            echo -e "${GREEN}    Remove USB and restart.                   ${NC}"
            echo -e "${GREEN}  ============================================${NC}"
            echo ""
        fi
        ;;

    3)
        echo ""
        echo "  Type 'exit' to return to menu"
        /bin/bash
        exec $0
        ;;

    *)
        echo "  Invalid choice"
        exec $0
        ;;
esac

read -p "  Press Enter..."
