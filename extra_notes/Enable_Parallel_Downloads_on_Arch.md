Notes From Repo: https://github.com/dillacorn/awtarchy

# Enable Parallel Downloads on Arch Linux

`sudo micro /etc/pacman.conf`

find `CTRL+f`

`#ParallelDownloads = 5`

remove the "`#`"

close & save file

`sudo pacman -Syu`

## Enjoy!