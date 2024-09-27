Setting up an Alpine Linux system as a tmux kiosk
=================================================

Edit `/etc/inittab` and comment out the `tty1` line, and replace it with the
following:

    #tty1::respawn:/sbin/getty 38400 tty1
    tty1::respawn:/bin/su - yourusername -c "/usr/bin/tmux new -s kiosk 'htop;/bin/bash'"

Save changes and reboot:

    lbu commit
    reboot

Whenever the machine boots up, it will start a new tmux session under the
username `yourusername`. The session will be called `kiosk` and it will run
`htop` followed by `bash`. If you want the kiosk to display anything else, just
`ssh` to the machine and attach to the session with `tmux a -t kiosk`. If you
quit `htop` it will give you a bash prompt.

For more sophisticated kiosk setups instead of tmux, you can replace the whole
`/usr/bin/tmux ...` with a script of your choice.

