My Server Installation: MyServer
================================
This documents a sample home server with the following features:

- Diskless Alpine linux running from RAM.
- Booted from a persistent USB stick that will contain its packages.
- Encrypted BTRFS on a typical SSD, where paths are mounted from subvolumes.
- Encrypted ZFS on a disk array, where paths are mounted from ZFS datasets.
- Disk encryption key is stored on the persistent USB stick.
- The persistent USB stick is automatically mounted under /root, and is only
  needed during boot or during update/upgrade.

Base installation
-----------------
Create a new Alpine Linux Extended installation on some virtual machine. Serve
the Alpine configuration (using `python3 -m http.server` or something) on
another machine on the network and install alpine using it:

    setup-alpine -f http://192.168.1.5:8000/myserver.alpine

Install necessary packages to clone this repo, check for the correct disk device
for USB, etc.

    apk add git lsblk

Make the installation persistent by writing it to a USB stick. Make *sure* you
check the correct device (e.g. /dev/sda), because that disk will be _wiped_.

    git clone https://erisc.se/infra/installers.git
    ./installers/diskless_alpine_on_persistent_usb.sh /dev/sdXYZ /root/myserver

Boot up the new machine using the USB-stick.

Prepare the encryption key
--------------------------

    head -c 32 /dev/random > /root/myserver/key.bin

Remember to back this up somewhere! You can encode it in base64 and store it in
your password manager.

    cat /root/myserver/key.bin | base64
    # will output something like umpDT9trXBxQugmz2fpAX4IqdeOSkrh4Fu2ZmDfYFAY=


Setup SSD for encrypted swap and some root directories
------------------------------------------------------
Install the dependencies:

    apk add btrfs-progs cryptsetup
    modprobe btrfs

Partition the SSD for swap and storage. Make sure you get the _correct_ device.

    export DISK=/dev/nvme0n1
    apk add sgdisk
    sgdisk --zap-all $DISK
    sgdisk -n 1:0:+96G -t 0:8200 $DISK
    sgdisk -n 2:0:0    -t 0:8300 $DISK
    mdev -s

Create swap. Remember to get the correct _partition_, e.g. `/dev/nvme0n1p1`

    ./installers/encrypted_swap.sh /dev/nvme0n1p1 /root/myserver/key.bin crypto-swap

Create encrypted BTRFS partition. Remember the get the correct _partition_, e.g.
`/dev/nvme0n1p2`

    ./installers/encrypted_btrfs_partition.sh /dev/nvmeXp2 \
                                              /root/myserver/key.bin \
                                              crypt-system \
                                              /home \
                                              /var/log \
                                              /opt \
                                              /lab

Setup RAIDZ pool on some other disks
------------------------------------
Install the dependencies:

    apk add zfs cryptsetup
    modprobe zfs

If you don't see any devices in `/dev/disk/by-id`, you might need to setup a
device manager:

    setup-devd udev

If you can see your disk drives in `/dev/disk/by-id`, then you are good to go.
Create the zfs pool:

    zpool create \
        -o ashift=12 \
        -O atime=off \
        -O mountpoint=none \
        -O encyrption=on \
        -O keylocation=file:///root/myserver/key.bin \
        -O keyformat=raw \
        storage raidz1 diskid1 diskid2 disk3

Create the datasets with given mount points:

    zfs create -o mountpoint=/archive storage/archive
    zfs create -o mountpoint=/entertainment storage/entertainment

Enable services:
    rc-update add zfs-import
    rc-update add zfs-load-key
    rc-update add zfs-mount

Commit LBU and you should be able to reboot.

    lbu commit
    reboot


Various tools and utils
-----------------------

Install some neat tools:

    apk add vim git bash bash-completion bash-doc coreutils

Enable community repos:

    vim /etc/apk/repositories

