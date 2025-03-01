#!/bin/sh

usage="
Installs Alpine on encrypted BTRFS using encrypted swap.

Usage:

    ./sys_alpine_with_encrypted_btrfs.sh <disk> [dir ...]

The script assumes you are running a fresh setup of Alpine Linux and just
executed 'setup-alpine', with 'none' on all the disk related options.

The script will wipe the given disk and create three partitions: an EFI
partition, a partition for swap, and the partition for the root filesystem that
will use BTRFS. It will create additional BTRFS subvolumes for each directory
specified as argument.

The following environment variables are used:

- BTRFS_OPTS: the BTRFS options
- EFI_SIZE: the size of the efi partition
- SWAP_SIZE: the size of the swap partition

Example:

    ./sys_alpine_with_encrypted_btrfs.sh /dev/sda /var/cache /var/log /home

"
disk="${1}"
shift
subvolume_dirs="/ $@"

BTRFS_OPTS="${BTRFS_OPTS:-defaults,noatime,nodiratime,discard=async,space_cache=v2,compress=zstd}"
EFI_SIZE="${EFI_SIZE:-260M}"
SWAP_SIZE="${SWAP_SIZE:-1G}"

# the crypto keyfile path is hardcoded in mkinitfs (doh!), which means we should
# probably stick to this path for future endeavours.
crypto_keyfile="/crypto_keyfile.bin"

if [ ! -e "$disk" ] ; then
    echo "$usage"
    exit 1
fi

# Install required packages
apk add sgdisk dosfstools cryptsetup btrfs-progs blkid
modprobe btrfs

# Zap the entire disk, and create EFI, swap, and system partitions
sgdisk --zap-all $disk
sgdisk -n 1:0:+$EFI_SIZE  -t 0:ef00 $disk
sgdisk -n 2:0:+$SWAP_SIZE -t 0:8200 $disk
sgdisk -n 3:0:0           -t 0:8300 $disk
mdev -s

# Get device path for each of the partitions
function device_path_for_partition {
    # turns "/dev/nvme0n0" "1" into /dev/nvme0n0p1"
    echo "$(echo "${1}" | sed "s/\([0-9]\)$/\1p/")$2"
}
efi_part="$(device_path_for_partition $disk 1)"
swap_part="$(device_path_for_partition $disk 2)"
system_part="$(device_path_for_partition $disk 3)"

# Create the LUKS container for the root file system. Note that it has to be of
# type luks1 since GRUB doesn't support luks2 for encrypted boot partition.
./create_luks_container.sh $system_part $crypto_keyfile root luks1

# Create the file system
partition="/dev/mapper/root"
mkfs.btrfs -f $partition

function subvolume {
    # turns e.g. "/var/log" into "@var_log"
    echo "@$(echo ${1/\//} | sed "s#/#_#g")"
}

# Create the subvolumes
mount $partition /mnt
for dir in $subvolume_dirs; do
    btrfs su cr /mnt/$(subvolume $dir)
done
umount /mnt

# Mount the subvolumes with the given BTRFS options
for dir in $subvolume_dirs; do
    mkdir -v -p /mnt/${dir/\//}
    mount -o "${BTRFS_OPTS},subvol=$(subvolume $dir)" $partition /mnt${dir%/}
done

# Setup the EFI partition
efi_dir=/boot/efi
mkfs.vfat -F32 $efi_part
mkdir -v -p /mnt$efi_dir
mount -t vfat $efi_part /mnt$efi_dir

# Enable dmcrypt so we can decrypt swap
rc-update add dmcrypt boot

# Setup encrypted swap
./encrypted_swap.sh $swap_part $crypto_keyfile swap

# Install Alpine on disk
#
# Note that GRUB installation will fail since we're trying to install GRUB on an
# encrypted device before we had a chance to set GRUB_ENABLE_ENCRYPTION. The
# setup will at least find appropriate modules for the hardware, so we ignore
# the error messages so we can do manual installation later.
export SWAP_DEVICES=/dev/mapper/swap
export KERNELOPTS="cryptkey quiet udev.log_priority=3"
setup-disk -m sys /mnt/


# Adding passphrase to the LUKS system container, so it can be unlocked by
# passphrase during boot. Note that we do this after we have created the LUKS
# containers and the crypto keyfile, since we want the key file (with low PBKDF
# iterations) in the first slot, to make it quick to unlock remaining
# partitions.
cryptsetup luksAddKey --key-file $crypto_keyfile $system_part

# Move the keyfile to the new system, this is quite important, so that it can be
# used by init to decrypt root and swap.
mv -v $crypto_keyfile "/mnt${crypto_keyfile}"

# We need to add configuration to GRUB to decrypt boot partition
echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub

# Prepare choot environment
mount -t proc /proc /mnt/proc
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --rbind /sys /mnt/sys

# Install GRUB
chroot /mnt apk add efibootmgr
chroot /mnt grub-install --target=x86_64-efi --efi-directory=$efi_dir
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Regenerate initfs, since we need to include our cryptkey feature (and actually
# pick up the encryption key we moved into target environment earlier)
sed -i 's/cryptsetup/& cryptkey/' /mnt/etc/mkinitfs/mkinitfs.conf
mkinitfs -c /mnt/etc/mkinitfs/mkinitfs.conf -b /mnt $(ls /mnt/lib/modules/)
