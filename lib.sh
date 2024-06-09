#!/bin/sh

set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    >&2 echo  "Must be root to execute this command."
    exit 1
fi

is_alpine_linux() {
    grep 'NAME="Alpine Linux"' /etc/os-release > /dev/null
}


device_path_for_partition() {
    # turns "/dev/nvme0n0" "1" into /dev/nvme0n0p1"
    echo "$(echo "${1}" | sed "s/\([0-9]\)$/\1p/")$2"
}

fstab_id() {
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
        echo "$key_file not found, so I'll generate a 512 bit random key for you."
        echo "REMEMBER TO BACK IT UP in your password storage somewhere!"
        head -c 64 /dev/random > $key_file
    fi

    # Format the LUKS container
    cryptsetup luksFormat \
        --batch-mode \
        --key-file $key_file \
        --pbkdf pbkdf2 \
        --pbkdf-force-iterations 1000 \
        --hash sha512 \
        $device

    # Open the LUKS container using our key
    cryptsetup luksOpen --key-file $key_file $device $name
}



