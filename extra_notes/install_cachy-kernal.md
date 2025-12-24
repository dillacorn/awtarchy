### CachyOS kernel on Arch (systemd-boot) quick guide

Automatic repo setup: use the **Quick Installation** section from `CachyOS/linux-cachyos` (the `cachyos-repo.sh` script). ([GitHub][1])

Install the kernel:

```sh
sudo pacman -Syu
sudo pacman -S --needed linux-cachyos linux-cachyos-headers
```

Create the systemd-boot entry (copy a known-good Arch entry so the `options ...` line stays correct):

```sh
cd /boot/loader/entries
ls
sudo cp -a 2025-05-07_00-19-11_linux.conf linux-cachyos.conf
sudo nano linux-cachyos.conf
```

`linux-cachyos.conf` should look like:

```ini
title   Linux CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /amd-ucode.img        # or /intel-ucode.img
initrd  /initramfs-linux-cachyos.img
options root=UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX rw
```

No “update” step is required for entry files. systemd-boot reads `loader/entries/*.conf` at boot. ([man7.org][2])

Verify it’s detected:

```sh
bootctl list
```

Boot menu tip: highlight an entry and press **d** to set it as the default (persistent via EFI variable). ([man7.org][2])

[1]: https://github.com/CachyOS/linux-cachyos?utm_source=chatgpt.com#quick-installation "CachyOS/linux-cachyos: Archlinux Kernel based on ..."
[2]: https://man7.org/linux/man-pages/man7/systemd-boot.7.html "systemd-boot(7) - Linux manual page"
