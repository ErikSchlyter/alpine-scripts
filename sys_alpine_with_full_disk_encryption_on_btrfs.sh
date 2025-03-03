#!/bin/sh

usage="
Installs Alpine on BTRFS with full disk encryption, including boot/swap.

Usage:

    ./sys_alpine_with_full_disk_encryption_on_btrfs.sh <disk> [dir ...]

The script assumes you are running a fresh setup of Alpine Linux and just
executed 'setup-alpine', with 'none' on all the disk related options.

The script will wipe the given disk and create two partitions: an EFI
partition, and a system partition. The system partition will contain an
encrypted LVM group, that will hold swap space and the root filesystem with
given BTRFS subvolume mounts.

The following environment variables can be used for custom configuration:

- BTRFS_OPTS: the BTRFS options
- KERNEL_MODULES: the kernel modules to include in the bootloader
- EFI_SIZE: the size of the EFI partition
- SWAP_SIZE: the size of the swap partition

Example:

    ./sys_alpine_with_encrypted_btrfs.sh /dev/sda /var/cache /var/log /home

"
disk="${1}"
shift
subvolume_dirs="/ $@"

BTRFS_OPTS="${BTRFS_OPTS:-defaults,noatime,nodiratime,discard=async,space_cache=v2,compress=zstd}"
KERNEL_MODULES="${KERNEL_MODULES:-sd-mod,usb-storage,nvme,btrfs}"
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
apk add sgdisk dosfstools cryptsetup btrfs-progs blkid lvm2 efibootmgr grub-efi
modprobe btrfs

# Zap the entire disk, and create the EFI and system partition
sgdisk --zap-all $disk
sgdisk -n 1:0:+$EFI_SIZE -t 0:ef00 $disk
sgdisk -n 2:0:0          -t 0:8300 $disk
mdev -s

# Get device path for each of the partitions
function device_path_for_partition {
    # turns "/dev/nvme0n0" "1" into /dev/nvme0n0p1"
    echo "$(echo "${1}" | sed "s/\([0-9]\)$/\1p/")$2"
}
efi_part="$(device_path_for_partition $disk 1)"
system_part="$(device_path_for_partition $disk 2)"

# Create the LUKS container for the root file system.
./create_luks_container.sh $system_part $crypto_keyfile lvmcrypt luks1

# Create LVM groups and volumes
pvcreate /dev/mapper/lvmcrypt
vgcreate vg0 /dev/mapper/lvmcrypt
lvcreate -L $SWAP_SIZE vg0 -n swap
lvcreate -l "100%FREE" vg0 -n root

# Create the file system on the root volume
partition="/dev/vg0/root"
mkfs.btrfs -f $partition

function subvolume {
    # turns e.g. "/var/log" into "@var_log"
    echo "@$(echo ${1/\//} | sed "s#/#_#g")"
}

# Create the BTRFS subvolumes
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

# Setup the EFI partition. Note that we use a separate directory for EFI
# (/boot/efi) and not directly in /boot, since we want /boot to be encrypted.
efi_dir=/boot/efi
mkfs.vfat -F32 $efi_part
mkdir -v -p /mnt$efi_dir
mount -t vfat $efi_part /mnt$efi_dir

# Setup swap
mkswap /dev/vg0/swap
swapon /dev/vg0/swap
rc-update add swap default

# Install Alpine on disk, but skip installing the bootloader.
export SWAP_DEVICES=/dev/vg0/swap
export BOOTLOADER=none
setup-disk -m sys /mnt/

# Adding passphrase to the LUKS container, so it can be unlocked during boot.
cryptsetup luksAddKey --key-file $crypto_keyfile $system_part

# Move the keyfile to the new system. This is quite important, so that it can be
# included in the initramfs so init to decrypt the system partition.
mv -v $crypto_keyfile "/mnt${crypto_keyfile}"

# Setup GRUB configuration
root_uuid="UUID=$(blkid -s UUID -o value $system_part)"
swap_uuid="UUID=$(blkid -s UUID -o value /dev/vg0/swap)"
kernel_opts="cryptroot=$root_uuid resume=$swap_uuid cryptdm=lvmcrypt cryptkey quiet udev.log_priority=3"
mkdir -p /mnt/etc/default
cat > /mnt/etc/default/grub <<- EOF
GRUB_TIMEOUT=2
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY=true
GRUB_CMDLINE_LINUX_DEFAULT="modules=$KERNEL_MODULES $kernel_opts"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=true
EOF

# Prepare choot environment, which we need when installing bootloader
mount -t proc /proc /mnt/proc
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --rbind /sys /mnt/sys

# Install GRUB as the bootloader
chroot /mnt grub-install --target=x86_64-efi --efi-directory=$efi_dir --boot-directory=/boot --bootloader-id=alpine
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Update mkinitfs configuration and regenerate initramfs, since we need to
# include our cryptkey feature and actually pick up the encryption key we moved
# into target environment earlier.
sed -i 's/cryptsetup/& cryptkey resume/' /mnt/etc/mkinitfs/mkinitfs.conf
mkinitfs -c /mnt/etc/mkinitfs/mkinitfs.conf -b /mnt $(ls /mnt/lib/modules/)
