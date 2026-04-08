#!/bin/bash
echo "=== Disk layout ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL

echo ""
echo "=== Finding largest NTFS partition ==="
DISK="sda"
best=""
best_size=0
for pname in $(lsblk -l -o NAME "/dev/$DISK" 2>/dev/null | tail -n +2 | grep -v "^${DISK}$"); do
    fs=$(blkid -o value -s TYPE "/dev/$pname" 2>/dev/null)
    if [ "$fs" = "ntfs" ]; then
        psz=$(blockdev --getsize64 "/dev/$pname" 2>/dev/null)
        [ -z "$psz" ] && continue
        szgb=$((psz / 1073741824))
        label=$(blkid -o value -s LABEL "/dev/$pname" 2>/dev/null)
        echo "  /dev/$pname: ${szgb}GB ntfs $label"
        if [ "$psz" -gt "$best_size" ]; then
            best_size=$psz
            best=$pname
        fi
    fi
done
echo "  LARGEST: /dev/$best ($((best_size/1073741824))GB)"

echo ""
echo "=== Mount test ==="
mkdir -p /srv/chumchim
grep -q "user_allow_other" /etc/fuse.conf 2>/dev/null || echo "user_allow_other" >> /etc/fuse.conf
ntfs-3g "/dev/$best" /srv/chumchim -o rw,big_writes,allow_other 2>&1
echo "Mount RC: $?"
df -h /srv/chumchim
touch /srv/chumchim/.writetest 2>&1
echo "Write RC: $?"
rm -f /srv/chumchim/.writetest

echo ""
echo "=== NFS export test ==="
echo "/srv/chumchim *(rw,sync,no_subtree_check,no_root_squash,insecure,fsid=1)" > /etc/exports
rpcbind 2>/dev/null
rpc.nfsd 8 2>/dev/null
rpc.mountd 2>/dev/null
exportfs -ra 2>/dev/null
exportfs -v 2>/dev/null | head -3
echo "NFS export RC: $?"

umount /srv/chumchim 2>/dev/null
echo ""
echo "=== DONE ==="
