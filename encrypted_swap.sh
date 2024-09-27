#!/bin/sh

usage="
Creates a LUKS container with encrypted swap on the given partition.

Requires: cryptsetup blkid

Usage:

   ./encrypted_swap.sh <device> <key-file> [name]

The <device> is the path to the partition to use, e.g. '/dev/sda1'.

The <key-file> is used to decrypt/open your LUKS container, which should
               contain random data with at least 256 bit entropy (see README.md)
               The file will be created if it doesn't exist. Remember to back it
               up in your password storage somewhere!

The [name] is optional for your crypt device, defaults to 'crypt-swap'.
"

device=$1
key_file=$2
name="${3:-crypt-swap}"

if [ ! -e "$device" ] || [ -z "$key_file" ]; then
    echo "$usage"
    exit 1
fi

$(dirname $0)/create_luks_container.sh "$device" "$key_file" "$name"

crypt_device="/dev/mapper/$name"
mkswap $crypt_device
swapon $crypt_device
rc-update add swap boot

echo -e "UUID=$(blkid $crypt_device -s UUID -o value)\tnone\tswap\tdefaults,noatime 0 0" >> /etc/fstab

# Note that we use 'target' here instead of 'swap' in dmcrypt configuration,
# since we only want dmcrypt to open the LUKS container. We'll enable swap
# via /etc/fstab and the openrc service.
cat <<EOT >> /etc/conf.d/dmcrypt

target=$name
source='$device'
key='$key_file'
EOT
