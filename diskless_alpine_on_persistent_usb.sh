#!/bin/sh
#
# Copy current Linux Alpine installation onto bootable and persistent USB
#
# Script assumes you are running a fresh diskless setup of Alpine Linux and just
# executed `setup-alpine.sh`, and that the Alpine installation is mounted under
# /media/cdrom.
#
# The script will wipe the given device, create a VFAT file system, and copy the
# current installation and make it bootable. It will update LBU and APK cache to
# use the USB.
#
# Usage:
#
#   ./diskless_alpine_on_persistent_usb.sh <device> [media]
#
# The optional parameter is just the name of the mount point under /media,
# which will default to `persistent`.
#
# Example:
#
#   ./diskless_alpine_on_persistent_usb.sh /dev/sda my_alpine

set -euo pipefail

device=${1}
media=${2:-persistent}

# install required packages
apk add sfdisk blkid

# wipe USB disk and create a bootable DOS partition
echo "label: mbr" | sfdisk $device
echo "type=83" | sfdisk $device
mdev -s
partition="${device}1"

# create the VFAT file system
mkfs.vfat -F32 $partition
modprobe vfat

# insert our USB media in the first line of /etc/fstab
# (TODO: don't know if it actually needs to be first, but we don't want our USB
# to be mounted to /dev/usbstick or something)
uuid=$(blkid $partition | sed 's/.* UUID="//' | sed 's/".*//')
echo -e "UUID=$uuid\t/media/$media\tvfat\tdefaults,noatime 0 0" > /tmp/fstab
cat /etc/fstab >> /tmp/fstab
mv /tmp/fstab /etc/fstab

# install our diskless Alpine installation on the disk
mkdir /media/$media
setup-bootable -v /media/cdrom /media/$media

# setup APK cache to our new media
setup-apkcache /media/$media/cache
sed -i "s#/media/cdrom/apks#/media/$media/apks#" /etc/apk/repositories

apk update

# setup LBU
setup-lbu $media
lbu commit
