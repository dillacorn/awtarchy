Notes From Repo: https://github.com/dillacorn/awtarchy

# list drives.

`sudo blkid`

# WARNING
If you mess up fstab your system will have issues starting. You will need to reboot into recovery mode and use "micro" to edit fstab again to fix the issues you may have caused.**

# edit fstab

`sudo micro /etc/fstab`

Create a new line at the end starting with "#" - add description for auto-mounting directory.

***example:***
`# secondary M.2 drive /dev/nvme1n1p1`

`UUID=e9d89909-b5b1-49e5-90b1-279004892fz21    /mnt/M2   btrfs   defaults   0   2`

save and reboot.

`sudo chown dillacorn:dillacorn /mnt/M2`

to view directory... use a terminal or file manager

`cd /mnt/M2`
