My various setup/installer scripts for Alpine Linux
===================================================

I use these scripts for my own setups. You can use them too, but I encourage you
to examine the scripts to actually understand what's going on. Some of the
scripts are compatible with other distributions (e.g. Arch), but it's been
developed for Alpine.

This document explains a sample home/office server with the following features:

- Diskless Alpine Linux running from RAM.
- Booted from a persistent USB stick that will contain all packages and
  configuration.
- Encrypted swap disk for RAM.
- Encrypted BTRFS on a typical SSD, where paths are mounted from subvolumes.
- Encrypted ZFS on a disk array, where paths are mounted from ZFS datasets.
- Disk encryption key is stored on the persistent USB stick.
- The persistent USB stick is automatically mounted under /root, and is only
  needed during boot or during update/upgrade.

This setup will give you a fast and minimal headless Linux installation running
entirely from RAM, while mounting various encrypted BTRFS and ZFS disks during
boot. Since the entire installation along with encryption key is stored on the
USB stick, the USB stick will act as your portable key for the entire system.
The system is assumed to be headless, so there's no password entry or additional
security beyond having physical access to the USB stick.

The USB stick is only necessary during boot, upgrades, reconfigurations, or when
installing new packages, so once the system is booted you may unplug the stick
and store it in your safe, your pocket, or that secret spot out in the woods
marked with an X, or wherever you store your secrets.

You don't _have_ to unplug it though, as perhaps the physical perimeters of your
computer is secure enough. Perhaps you only want to be able to take your key
with you when your're out and about, or when putting the machine in cold
storage, or while transporting it to a new location, or whatever. Keeping the
USB stick plugged in may make it more convenient to perform upgrades,
reconfigurations, etc. It is up to you.


Base installation
-----------------
Download [Alpine Linux Extended](https://alpinelinux.org/downloads/) and either
boot it up on some virtual machine (I prefer using [QEMU](https://www.qemu.org))
or an another actual computer. Edit the Alpine configuration (`myserver.alpine`)
to your liking, and serve it (using `python3 -m http.server` or something) from
your host so you can reach it from the alpine machine.

Note that you need to serve your public SSH key as well (e.g. `mykey.pub`),
otherwise the installer script will not be able to pick it up, and you will not
be able to connect to your newly installed target machine once basic setup is
complete.

Boot up the Alpine image on your virtual machine, login as root, and execute the
basic Alpine setup:

    setup-alpine -f http://yourhostip:8000/myserver.alpine

Get the scripts into the Alpine virtual machine
-----------------------------------------------
You need to install `git` to clone this repo, `lsblk` to check the correct
disk device for USB, and the proper version of `blkid` to get UUID, etc.

    apk add git lsblk blkid

You can either clone this repo from a public source:

    git clone https://github.com/ErikSchlyter/alpine-scripts.git
    cd alpine-scripts

...or, since you're already serving your directory via HTTP, you can simply
clone it from there. Just make sure you have executed `git update-server-info`
in your host repo first.

    git clone https://yourhostip:8000/.git alpine-scripts
    cd alpine-scripts

Insert the USB stick and make it available for your virtual machine, then use
`lsblk` to check the device name of your USB. Make *sure* you check the correct
device (e.g. `/dev/sda`), because that disk will be _wiped_.

Once you know the device path, make the installation persistent by writing it to
a USB stick and specifying the desired mount point (somehere under `/root/` is a
neat choice):

    ./diskless_alpine_on_persistent_usb.sh /dev/sdXYZ /root/myserver

Close your virtual machine and boot up the actual target machine using the
USB-stick.

On the target machine
---------------------
The rest of the instructions are assuming that you are connected to the newly
booted target machine via SSH.

Prepare the encryption key
--------------------------

    head -c 32 /dev/random > /root/myserver/key.bin

Remember to back this up somewhere! If your USB stick gets lost or destroyed,
you will never be able to access your other disks on the target system ever
again. You can encode the key in base64 and store it in your password manager.

    base64 < /root/myserver/key.bin
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

    ./encrypted_swap.sh /dev/nvme0n1p1 /root/myserver/key.bin crypt-swap

Create encrypted BTRFS partition and move desired directories into it. Remember
the get the correct _partition_, e.g.  `/dev/nvme0n1p2`

    ./encrypted_btrfs_partition.sh /dev/nvmeXp2 \
                                   /root/myserver/key.bin \
                                   crypt-system \
                                   /home \
                                   /var/log \
                                   /opt

Setup RAIDZ pool on some other disks
------------------------------------
Install the dependencies:

    apk add zfs cryptsetup
    modprobe zfs

If you don't see any devices in `/dev/disk/by-id`, you might need to setup a
device manager:

    setup-devd udev

If you can see your disk drives in `/dev/disk/by-id`, then you are good to go.
Create the zfs pool named `storage` (or whatever you want):

    zpool create \
        -o ashift=12 \
        -O atime=off \
        -O mountpoint=none \
        -O encyrption=on \
        -O keylocation=file:///root/myserver/key.bin \
        -O keyformat=raw \
        storage raidz1 <diskid1> <diskid2> <diskid3>

Create the desired datasets with given mount points:

    zfs create -o mountpoint=/archive storage/archive
    zfs create -o mountpoint=/media storage/media

Enable services:

    rc-update add zfs-import
    rc-update add zfs-load-key
    rc-update add zfs-mount

Commit LBU and you should be able to reboot.

    lbu commit

Your system should now be up and running. Try a `reboot` to confirm that
everything works as expected. Enjoy!



Important notice regarding key file and PBKDF iterations
--------------------------------------------------------
If you use any of the disk encryption functions, you should generate a random
key file that contains at least as much entropy as the output of the key
derivation function (e.g. `head -c 32 /dev/random > my_key.bin` for a 256 bit
key) rather than an actual passphrase. If the key file already contains that
much entropy, a PBKDF iteration will not yield any additional security since it
will be easier to just attack the output of the key derivation function rather
than the actual key file (and our sun will not generate enough energy to let
that happen, given the amount of combinations a computer must attempt to
brute-force a 256 bit key).

This means we can set the `pbkdf-force-iterations` to lowest allowed value (i.e.
1000), making it really fast to decrypt the cipher key.

You should also put the key file as the first LUKS key slot, since that will be
attempted first and will be verified very quickly. If you want to add actual
passphrases to your setup as a backup, add them in the following key slots, but
then you *must use proper parameters* for your key derivation function. Current
default is to use argon2id with 2000 ms iteration time. Once you have your key
file, you can add an additional passphrase with the following command:

    cryptsetup luksAddKey --key-file my_key.bin /dev/sda1


