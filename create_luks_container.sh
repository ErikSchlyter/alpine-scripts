#!/bin/sh

usage="
Creates a LUKS container on the given device partition, using the specified key
file. If the key file doesn't exist, it will be created with 256 bit random
data. Once created, the container will also be opened.

IMPORTANT NOTICE: It is assumed that the key file contains proper amount of
entropy (e.g. 256 bit), because the PBKDF function will be set to minimum
iterations. Do NOT use a simple password in the keyfile!

Requires: cryptsetup

Usage:

    ./create_luks_container.sh <device-partition> <key-file> <name>

Examples:

    ./create_luks.container.sh /dev/sda1 /crypto-keyfile.bin crypt-system

"

device_partition=$1
key_file=$2
name=$3

if [ ! -e "$device_partition" ] || [ -z "$key_file" ] || [ -z "$name" ]; then
    echo "$usage"
    exit 1
fi

if [ ! -f $key_file ]; then
    >&2 echo "$key_file not found, so I'll generate a 256 bit random key for you."
    >&2 echo "REMEMBER TO BACK IT UP in your password storage somewhere!"
    head -c 32 /dev/random > $key_file
fi

# Format the LUKS container
cryptsetup luksFormat \
    --batch-mode \
    --key-file $key_file \
    --pbkdf pbkdf2 \
    --pbkdf-force-iterations 1000 \
    $device_partition

# Open the LUKS container using our key
cryptsetup luksOpen --key-file $key_file $device_partition $name
