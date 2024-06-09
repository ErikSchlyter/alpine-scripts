#!/bin/sh
#
# Creates a BTRFS subvolume on the given device, and replaces the given path
# with a mount that is added to /etc/fstab
#
# requires: blkid btrfs-progs
#
# usage:
#
#   btrfs_subvol_fstab.sh <device> <mount_path>
#
# examples:
#
#   ./btrfs_subvol_fstab.sh /dev/sdb1 /var/cache
#   ./btrfs_subvol_fstab.sh /dev/mapper/encrypted_home /home
#

set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    echo "Must be executed as root"
    exit 1
fi

. ./lib.sh

BTRFS_OPTS="${BTRFS_OPTS:-defaults,noatime,discard=async,space_cache=v2,compress=lzo}"

device="$1"
mount_path="$2"


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
        mkdir -v -p $mount_path
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
