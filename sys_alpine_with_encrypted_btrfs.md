Alpine Linux system on encrypted BTRFS root, with encrypted swap and boot (GRUB)
================================================================================

This document explains how to perform a Alpine Linux system installation with
the following features:

- Encrypted BTRFS on root, with distinct submodules.
- Encrypted swap disk for RAM.
- Encrypted boot using GRUB.

The reason to use this script instead of the default procedure in `setup-disk`
is because it mounts root to a BTRFS subvolume, and it encrypts swap on a
separate partition. It's also easier to setup/configure additional partitions.

Base installation
-----------------
Download [Alpine Linux Standard](https://alpinelinux.org/downloads/), write it
to a USB stick and boot up on the target machine. Execute the classic
`setup-alpine`, but choose `none` on the disk options. This will setup the
environment to your liking.

Get the scripts into the new target machine
-------------------------------------------
You need to install `git` to clone this repo, and `lsblk` to check the correct
disk device for USB.

    apk add git lsblk

You can either clone this repo from a public source:

    git clone https://github.com/ErikSchlyter/alpine-scripts.git
    cd alpine-scripts

...or, you can serve the repo (along with your own custom configuration) from
another machine on the local network using `python3 -m http.server`. Just make
sure you have executed `git update-server-info` in your host repo first.

    git clone http://yourhostip:8000/.git alpine-scripts
    cd alpine-scripts

System installation to disk
---------------------------
Execute the script with the device as argument, followed by the desired BTRFS
subvolume paths:

    ./sys_alpine_with_encrypted_btrfs.sh /dev/nvme0n0 /var/cache /var/log /home

