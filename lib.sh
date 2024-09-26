#!/bin/sh

set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    >&2 echo  "Must be root to execute this command."
    exit 1
fi

device_path_for_partition() {
    # turns "/dev/nvme0n0" "1" into /dev/nvme0n0p1"
    echo "$(echo "${1}" | sed "s/\([0-9]\)$/\1p/")$2"
}

fstab_id() {
    # Gives the device id to use in fstab entry, which is the UUID
    device=$1
    if uuid=$(blkid $device | sed 's/.* UUID="//' | sed 's/".*//'); then
        echo "UUID=$uuid"
    else
        echo $device
    fi
}

create_luks_container() {
    device=$1
    key_file=$2
    name=$3

    if [ ! -f $key_file ]; then
        echo "$key_file not found, so I'll generate a 256 bit random key for you."
        echo "REMEMBER TO BACK IT UP in your password storage somewhere!"
        head -c 32 /dev/random > $key_file
    fi

    # Format the LUKS container
    cryptsetup luksFormat \
        --batch-mode \
        --key-file $key_file \
        --pbkdf pbkdf2 \
        --pbkdf-force-iterations 1000 \
        $device

    # Open the LUKS container using our key
    cryptsetup luksOpen --key-file $key_file $device $name
}



