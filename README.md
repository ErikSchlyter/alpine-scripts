My various setup/installer scripts for Alpine Linux
===================================================

I use these scripts for my own setups. You can use them too, but I encourage you
to examine the scripts to actually understand what's going on.

Use them at your own risk. Cheers!



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
passphrases to your setup, add them in the following key slots, but then you
*must use proper parameters* for your key derivation function. Current default
is to use argon2id with 2000 ms iteration time. Once you have your key file, you
can add an additional passphrase with the following command:

    cryptsetup luksAddKey --key-file my_key.bin /dev/sda1


