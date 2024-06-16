#!/bin/sh

usage="
Replaces a given directory path with a BTRFS subvolume that will be created on
the given device. The new subvolume will be named after the path (slashes
replaced and such), and the path will be added as an entry in /etc/fstab. If the
mount path already exist, the contents will be copied to the newly mounted
subvolume.

Requires: blkid btrfs-progs

Usage:

    ./replace_path_with_btrfs_subvol.sh <mount_path> <device>

Examples:

    ./replace_path_with_btrfs_subvol.sh /var/cache /dev/sdb1
    ./replace_path_with_btrfs_subvol.sh /home /dev/mapper/encrypted_home

"

BTRFS_OPTS="${BTRFS_OPTS:-defaults,noatime,discard=async,space_cache=v2,compress=lzo}"

mount_path="$1"
device="$2"

if [ ! -e "$device" ] || [ -z "$mount_path" ]; then
    echo "$usage"
    exit 1
fi

. $(dirname $0)/lib.sh

# turns "/var/cache" into "@var_cache", or "/" into "@"
subvolume=$(echo "@$(echo ${mount_path/\//} | sed "s#/#_#g")")
subvolume_path="/mnt/$subvolume"

mount $device /mnt
btrfs su create $subvolume_path
echo -e "$(fstab_id $device)\t$mount_path\tbtrfs\tsubvol=$subvolume,$BTRFS_OPTS 0 0" >> /etc/fstab

if [ "$mount_path" != "/" ]; then
    if [ -d $mount_path ]; then # the mount path already exists
        # move the old content into the new subvolume
        for f in $mount_path/* $mount_path/.[!.]* $mount_path/..?*; do
            if [ -e "$f" ]; then mv -- "$f" $subvolume_path/; fi
        done
    fi
    mkdir -v -p $mount_path
    mount $mount_path
fi

umount /mnt
