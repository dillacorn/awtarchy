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

## NVIDIA NOTICE!

If awtarchy was installed before CachyOS repos and kernel were added, rerun `install_GPU_dependencies.sh` after `linux-cachyos` is installed.

```bash
./awtarchy/scripts/install_GPU_dependencies.sh
```

Why this matters:
- early NVIDIA module injection into `mkinitcpio.conf` before Cachy exists can make the later Cachy initramfs generation fail
- when that happens, systemd-boot may show:
  `Error preparing initrd: Not found`
- the actual missing file is usually `/boot/initramfs-linux-cachyos.img`

Safer order for NVIDIA users:
1. Install awtarchy.
2. Add CachyOS repos.
3. Install `linux-cachyos` and `linux-cachyos-headers`.
4. Reboot once into the Cachy kernel.
5. Run awtarchy `install_GPU_dependencies.sh` again so NVIDIA kernel integration is applied against the final installed kernel layout.

If using the patched awtarchy GPU script, the first awtarchy install will defer NVIDIA bootloader and mkinitcpio changes until a Cachy kernel is already present.
