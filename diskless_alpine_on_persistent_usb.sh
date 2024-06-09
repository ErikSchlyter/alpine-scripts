#!/bin/sh

usage="
Copy current Linux Alpine installation onto bootable and persistent USB stick.

Usage:

    ./diskless_alpine_on_persistent_usb.sh <device> [mount-point]

The script assumes you are running a fresh diskless setup of Alpine Linux and
just executed 'setup-alpine', and that the Alpine installation is mounted under
/media/cdrom.

The script will wipe the given USB device, create a VFAT file system, and copy
the current installation and make it bootable. It will update LBU and APK cache
to use the USB.

The optional parameter is the mount point of the USB device, which defaults to
/media/persistent.

Hint: You can set the mount point to a directory under root, and only the root
user will have read access to the USB stick. This is useful when you also want
to use your USB stick as a 'portable key', by storing LUKS encryption keys on
the USB stick that automatically unlocks other disks on the machine during boot.

Example:

    ./diskless_alpine_on_persistent_usb.sh /dev/sda /root/my_alpine

"

device=${1}
mount_point=${2:-/media/persistent}
if [ ! -e $device ]; then
    echo $usage
    exit 1
fi


. $(dirname $0)/lib.sh

# install required packages
apk add sfdisk blkid

# wipe USB disk and create a bootable DOS partition
echo "label: mbr" | sfdisk $device
echo "type=83" | sfdisk $device
mdev -s

# create the VFAT file system
partition="${device}1"
mkfs.vfat -F32 $partition
modprobe vfat

# add our USB media to /etc/fstab
echo -e "$(fstab_id $partition)\t$mount_point\tvfat\tdefaults,noatime 0 0" >> /etc/fstab

# install our diskless Alpine installation on the disk
mkdir -p -v $mount_point
setup-bootable -v /media/cdrom $mount_point

# update apk repo path
sed -i "s#/media/cdrom/apks#$mount_point/apks#" /etc/apk/repositories

# setup APK cache to our new media
setup-apkcache $mount_point/cache

apk update
apk cache download
apk cache purge

# setup LBU to use our mount point as backup dir.
sed -i "s%^# *LBU_BACKUPDIR=.*%LBU_BACKUPDIR=$mount_point%" /etc/lbu/lbu.conf

# it is important to exclude the mount path from LBU in case you mount it under
# a folder that is already included (e.g., /root/), otherwise lbu commit will go
# haywire in an endless loop that consumes all memory.
lbu exclude $mount_point

lbu commit
