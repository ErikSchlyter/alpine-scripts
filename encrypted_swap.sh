#!/bin/sh
#
# Creates a LUKS container with encrypted swap on the given partition.
#
# usage:
#
#   ./encrypted_swap.sh <device> <key-file> [name]
#
#   The <device> is the path to the partition to use, e.g. `/dev/sda1`.
#
#   The <key-file> is used to decrypt/open your LUKS container, which should
#                  contain random data with at least 512 bit entropy (see
#                  important notes below). The file will be created if it
#                  doesn't exist. Remember to back it up!
#
#   The [name] is optional for your crypt device, defaults to 'crypt-swap'.
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
name="${3:-crypt-swap}"

# install necessary dependencies
apk add cryptsetup

create_luks_container "$device" "$key_file" "$name"

crypt_device="/dev/mapper/$name"
mkswap $crypt_device
swapon $crypt_device
#rc-update add swap boot

echo -e "$(fstab_id $crypt_device)\tswap\tswap\tdefaults,noatime 0 0" >> /etc/fstab

cat <<EOT >> /etc/conf.d/dmcrypt

swap=$name
source='$device'
key='$key_file'
EOT

