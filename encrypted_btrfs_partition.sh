#!/bin/sh
#
# Creates a LUKS container with BTRFS file system on the given partition in a
# diskless Alpine Linux setup. The script assumes the encrypted device will be
# an additional disk explicitly different from the medium the environment was
# booted from (which would probably be a USB stick).
#
# usage:
#
#   ./encrypted_btrfs_partition <device> <key-file> <name> [<directory> ...]
#
#   The <device> is the path to the partition to use, e.g. `/dev/sda1`.
#
#   The <key-file> is used to decrypt/open your LUKS container, which should
#                  contain random data with at least 512 bit entropy (see
#                  important notes below). The file will be created if it
#                  doesn't exist. Remember to back it up!
#
#   The <name> is whatever you want to name your encrypted device.
#
#   The optional directories will be moved into the newly encrypted device, and
#   there will be an /etc/fstab entry created for each of them. Note that root
#   (`/`) is not supported.
#
# example:
#
#   ./encrypted_btrfs_partition /dev/sda1 \
#                               /root/myusbstick/crypto_keyfile.bin \
#                               my-crypt-partition \
#                               /home \
#                               /opt \
#                               /var/log
#
# Important notice regarding key file and PBKDF iterations: You should generate
# a random key file that contains at least as much entropy as the output of the
# key derivation function (e.g. `head -c 64 /dev/random > my_key.bin` for a 512
# bit key) rather than an actual passphrase. If the key file already contains
# that much entropy, a PBKDF iteration will not yield any additional security
# since it will be easier to just attack the output of the key derivation
# function rather than the actual key file (and our sun will not generate enough
# energy to let that happen, given the amount of combinations a computer must
# attempt to brute-force a 512 bit key).
#
# This means we can set the `pbkdf-force-iterations` to lowest allowed value
# (i.e. 1000), making it really fast to decrypt the cipher key.
#
# You should also put the key file as the first LUKS key slot, since that will
# be attempted first and will be verified very quickly. If you want to add
# actual passphrases to your setup, add them in the following key slots, but
# then you MUST USE PROPER PARAMETERS for your key derivation function. Current
# default is to use argon2id with 2000 ms iteration time. You can add a
# passphrase with the following command:
#
#   cryptsetup luksAddKey --key-file my_key.bin /dev/sda1
#

set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    echo "Must be executed as root"
    exit 1
fi

. ./lib.sh

device=$1
key_file=$2
name=$3
shift 3
directories="${@%\/}"

# install necessary dependencies
apk add cryptsetup btrfs-progs
modprobe btrfs

if [ ! -f $key_file ]; then
    echo "$key_file not found, so I'll generate a 512 bit random key for you."
    echo "REMEMBER TO BACK IT UP in your password storage somewhere!"
    head -c 64 /dev/random > $key_file
fi

create_luks_container "$device" "$key_file" "$name"

crypt_device="/dev/mapper/$name"
mkfs.btrfs $crypt_device

# Move desired folders into the encrypted partition and update /etc/fstab
for directory in $directories; do
    ./create_btrfs_subvol.sh $crypt_device $directory
done

# Make sure the partition is decrypted upon boot
rc-update add dmcrypt boot
cat <<EOT >> /etc/conf.d/dmcrypt

target=$name
source='$device'
key='$key_file'
EOT

