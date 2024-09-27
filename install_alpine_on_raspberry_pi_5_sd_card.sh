#!/bin/sh
usage="
Install Alpine Linux on a Raspberry Pi 5 SD card.

This is a proof of concept. It's been a while since I tried it. Run this script
at your own risk. Download the Raspberry Pi image from Alpine's web page.

usage:

    ./install_alpine_on_raspberry_pi_5_sd_card.sh \
        <device-for-SD-card> \
        alpine-rpi-3.19.1-aarch64.tar.gz

"
disk=$1
rp_tgz="${2:-alpine-rpi-3.19.1-aarch64.tar.gz}"

if [ ! -e "$disk" ] || [ ! -e "$rp_tgz" ]; then
    echo "$usage"
    exit 1
fi

sgdisk --zap-all $disk
# create boot partition of type W95 FAT32 (LBA)
sgdisk -n 1:0:+1G -t 0:0c00 $disk
sgdisk -n 2:0:+4G -t 0:8200 $disk
sgdisk -n 3:0:0   -t 0:8300 $disk

mkfs.vfat -F32 "${disk}1"
mkswap "${disk}2"

mount "${disk}1" /mnt
tar xzf $rp_tgz -C /mnt/
cat <<EOF > /mnt/usercfg.txt
# Enable DRM VC4 V3D driver
dtoverlay=vc4-kms-v3d
max_framebuffers=2

# Don't have the firmware create an initial video= setting in cmdline.txt.
# Use the kernel's default instead.
disable_fw_kms_setup=1
EOF
umount /mnt
rmdir $mnt
