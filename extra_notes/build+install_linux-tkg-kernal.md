# Install linux-tkg on Arch (systemd-boot) — Generic CPU Guide

Simple, architecture-agnostic steps. Works for AMD and Intel.

---

## 0) Prerequisites

```sh
sudo pacman -S --needed base-devel git mkinitcpio micro
# Install your CPU microcode (pick ONE that matches your CPU vendor):
# AMD:
sudo pacman -S --needed amd-ucode
# Intel:
# sudo pacman -S --needed intel-ucode
```

---

## 1) Build linux-tkg

```sh
git clone https://github.com/Frogging-Family/linux-tkg.git
cd linux-tkg
makepkg -si
```

During prompts (keep it general and safe):
- Scheduler: `eevdf` is the upstream default and a good baseline. You can experiment later.
- Timer: `1000 Hz` is common for desktop/gaming. `300 Hz` is fine for servers.
- Tickless: `Just tickless idle` is a safe default. Full tickless is for core isolation users.
- Microarchitecture: choose one that matches your CPU, or `native` if you only boot this kernel on this exact machine.
  - To explore supported strings:
    - Clang: `clang -mcpu=help`
    - GCC: `gcc --target-help | grep -A 2 -m1 'Known valid' | sed -n '2p'`

This compiles the kernel and attempts to install the produced packages.

---

## 2) If install FAILED due to sudo timeout

Symptoms in log:

```
==> Installing ... with pacman -U...
sudo: timed out reading password
==> WARNING: Failed to install built package(s).
```

Manual install:

```sh
# From the same linux-tkg build directory
ls -1 *.pkg.tar.zst
# Example:
# linuxXYZ-tkg-<sched>-<ver>-x86_64.pkg.tar.zst
# linuxXYZ-tkg-<sched>-headers-<ver>-x86_64.pkg.tar.zst

sudo pacman -U ./linux*-tkg-*.pkg.tar.zst
# Add headers only if you need to build external modules/DKMS.
```

---

## 3) Verify kernel artifacts in /boot

```sh
ls -1 /boot | grep -E 'vmlinuz|initramfs|tkg|ucode'
# Expect to see, for example:
# vmlinuz-linuxXYZ-tkg-<sched>
# initramfs-linuxXYZ-tkg-<sched>.img
# initramfs-linuxXYZ-tkg-<sched>-fallback.img
# amd-ucode.img OR intel-ucode.img (whichever you installed)
```

If missing, the package didn’t install. Return to step 2.

---

## 4) systemd-boot entry

List current entries:

```sh
ls /boot/loader/entries
```

Create a new entry for linux-tkg. Use your existing Arch entry as a template to preserve your `options` line (root device, filesystem flags, etc.).

### 4.1 Template (replace placeholders)

```ini
# /boot/loader/entries/linux-tkg.conf
title   Linux TKG <VERSION_TAG>
linux   /vmlinuz-<VMLINUZ_NAME>
# Use ONE microcode line that matches your CPU vendor. If you don't have the file, delete that line.
# AMD microcode:
initrd  /amd-ucode.img
# Intel microcode:
# initrd  /intel-ucode.img
# Kernel initramfs:
initrd  /initramfs-<INITRAMFS_NAME>.img
options <COPY OPTIONS FROM YOUR WORKING ENTRY UNCHANGED>
```

Placeholders:
- `<VERSION_TAG>`: free-form label, e.g. `6.x.y-tkg`.
- `<VMLINUZ_NAME>`: the exact filename under `/boot`, e.g. `linux616-tkg-eevdf`.
- `<INITRAMFS_NAME>`: same base name as the kernel, e.g. `linux616-tkg-eevdf`.
- `<COPY OPTIONS FROM YOUR WORKING ENTRY UNCHANGED>`: your current Arch entry’s `options` line. Keep your `root=UUID|PARTUUID`, filesystem, zswap, and subvol flags exactly as-is.

### 4.2 Concrete example (ext4)

```ini
# /boot/loader/entries/linux-tkg.conf
title   Linux TKG 6.16.x
linux   /vmlinuz-linux616-tkg-eevdf
initrd  /amd-ucode.img        # or /intel-ucode.img for Intel
initrd  /initramfs-linux616-tkg-eevdf.img
options root=PARTUUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX rw rootfstype=ext4 quiet
```

### 4.3 Concrete example (btrfs with subvol=@)

```ini
# /boot/loader/entries/linux-tkg.conf
title   Linux TKG 6.16.x
linux   /vmlinuz-linux616-tkg-eevdf
initrd  /intel-ucode.img      # or /amd-ucode.img for AMD
initrd  /initramfs-linux616-tkg-eevdf.img
options root=PARTUUID=YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY rw rootflags=subvol=@ rootfstype=btrfs quiet
```

Optional fallback entry:

```ini
# /boot/loader/entries/linux-tkg-fallback.conf
title   Linux TKG 6.16.x (fallback)
linux   /vmlinuz-linux616-tkg-eevdf
initrd  /amd-ucode.img        # or /intel-ucode.img
initrd  /initramfs-linux616-tkg-eevdf-fallback.img
options <SAME AS YOUR NORMAL ENTRY>
```

Tip to get your current root PARTUUID:

```sh
blkid -s PARTUUID -o value "$(findmnt -no SOURCE /)"
```

---

## 5) Update boot loader

```sh
sudo bootctl update
bootctl list
```

You should see `linux-tkg.conf`.

Optional: make systemd-boot remember the last selection:

```sh
sudo micro /boot/loader/loader.conf
```

```ini
default @saved
timeout 3
#console-mode keep
```

---

## 6) Reboot and select the kernel

Pick the `Linux TKG` entry. Keep your stock and LTS entries for rollback.

---

## 7) Post-boot checks

```sh
uname -r
# Expect a tkg-suffixed version, e.g. 6.16.x-*-tkg-<sched>

# Optional sanity:
lsmod | head
```

---

## Notes

- Two `initrd` lines are expected: first microcode (AMD or Intel), then the kernel’s initramfs.
- `mkinitcpio -P` is not needed here; linux-tkg packages ship their initramfs. Run it only if you changed hooks or need to regenerate manually.
- Scheduler, HZ, and tickless choices are workload-dependent. Start with defaults, measure, then iterate.
