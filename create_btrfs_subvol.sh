#!/bin/sh

usage="
Creates a BTRFS subvolume on the given device, and replaces the given path
with a mount that is added to /etc/fstab. If the mount path already exist, the
contents will be copied to the newly mounted subvolume.

Requires: blkid btrfs-progs

Usage:

    ./create_btrfs_subvol.sh <device> <mount_path>

Examples:

    ./create_btrfs_subvol.sh /dev/sdb1 /var/cache
    ./create_btrfs_subvol.sh /dev/mapper/encrypted_home /home

"

BTRFS_OPTS="${BTRFS_OPTS:-defaults,noatime,discard=async,space_cache=v2,compress=lzo}"

device="$1"
mount_path="$2"

if [ ! -e "$device" ] || [ -z "$mount_path" ]; then
    echo "$usage"
    exit 1
fi

. $(dirname $0)/lib.sh

# turns "/var/cache" into "@var_cache", or "/" into "@"
subvolume=$(echo "@$(echo ${mount_path/\//} | sed "s#/#_#g")")

mount $device /mnt
btrfs su create "/mnt/$subvolume"
echo -e "$(fstab_id $device)\t$mount_path\tbtrfs\tsubvol=$subvolume,$BTRFS_OPTS 0 0" >> /etc/fstab

if [ "$mount_path" != "/" ]; then
    if [ -d $mount_path ]; then # the mount path already exists
        tmp_dir="/tmp/$subvolume"
        # move current mount -path to a temporary directory
        mv $mount_path $tmp_dir

        # create the mount path and mount our new subvolume
        mkdir -p $mount_path
        mount $mount_path

        # move the old content from temporary dir into the new mount path
        for f in $tmp_dir/* $tmp_dir/.[!.]* $tmp_dir/..?*; do
            if [ -e "$f" ]; then mv -- "$f" $mount_path/; fi
        done
        rmdir $tmp_dir
    else
        mkdir -v -p $mount_path
        mount $mount_path
    fi
fi

umount /mnt
