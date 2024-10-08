#!/bin/sh

usage="
Creates a LUKS container with BTRFS file system on the given partition using the
given key file (which is assumed to contain 256 bit of entropy).

The script assumes the encrypted device will be an additional disk explicitly
different from the medium the environment was booted from (which would probably
be a USB stick). Hence, it is not possible to create a subvolume for root folder
using this script.

Requires: cryptsetup btrfs-progs

Usage:

    ./encrypted_btrfs_partition <device> <key-file> <name> [<directory> ...]

The <device> is the path to the partition to use, e.g. '/dev/sda1'.

The <key-file> is used to decrypt/open your LUKS container, which should
               contain random data with at least 256 bit entropy (see README.md)
               The file will be created if it doesn't exist. Remember to back it
               up in your password storage somewhere!

The <name> is whatever you want to name your encrypted device.

The optional directories will be moved into the newly encrypted device, and
there will be an /etc/fstab entry created for each of them. Note that root ('/')
is not supported.

Example:

    ./encrypted_btrfs_partition /dev/sda1 \\
                                /root/myusbstick/crypto_keyfile.bin \\
                                my-crypt-partition \\
                                /home \\
                                /opt \\
                                /var/log

"

self_path="$(dirname $0)"
device=$1
key_file=$2
name=$3
shift 3
directories="${@%\/}"

if [ ! -e "$device" ] || [ -z "$key_file" ] || [ -z "$name" ]; then
    echo -e "$usage"
    exit 1
fi


$self_path/create_luks_container.sh "$device" "$key_file" "$name"

crypt_device="/dev/mapper/$name"
mkfs.btrfs $crypt_device

# Move desired folders into the encrypted partition and update /etc/fstab
for directory in $directories; do
    $self_path/replace_path_with_btrfs_subvol.sh $directory $crypt_device
done

# Make sure the partition is decrypted upon boot
rc-update add dmcrypt boot
cat <<EOT >> /etc/conf.d/dmcrypt

target=$name
source='$device'
key='$key_file'
EOT
