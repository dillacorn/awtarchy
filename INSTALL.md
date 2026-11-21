# Installing Awtarchy

Awtarchy is an Arch Linux desktop overlay, not a distribution or a base OS installer. **Vanilla Arch Linux (recommended) and CachyOS are supported installation bases.**

## Install a supported base first

For a new machine:

1. **Recommended:** install [vanilla Arch Linux](https://archlinux.org/download/) using `archinstall` with the **Minimal** profile, or follow the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) for manual installation.
2. **Alternatively:** install [CachyOS](https://cachyos.org/) using its official installer. A minimal setup is preferable, but an existing working CachyOS desktop can be used.
3. Boot into your installed system and log in before running Awtarchy.

Awtarchy overlays its own Quickshell desktop and managed configuration. Hyprland is the default compositor; Sway and Umbriel are optional sessions. CachyOS-specific safeguards preserve existing driver/network/display-manager state where practical, but installed desktop configuration may still be updated by Awtarchy. See [CachyOS compatibility notes](docs/cachyos-compatibility.md).

## Install Awtarchy

Install Git, clone the repository, and run the installer:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

The installer lets you choose **Hyprland (default)**, **Sway**, or **Both**.
Selecting Both provides independently selectable Ly sessions and separate
compositor/Quickshell profiles, while sharing desktop applications.
Sway uses `nwg-displays` (`Super+Ctrl+M`) for monitor settings; Hyprland
continues using Hyprmoncfg. Adding Sway from an active Hyprland session
imports the current display layout once when safe, but never overwrites a
personalized Sway layout. SwayFX is not part of this release.
After installation, `awtarchy compositor` can install Umbriel alongside
Hyprland or Sway, keeping the compositor and Quickshell configurations separate.

The installer collects the relevant hardware/package choices before applying the overlay. Dependencies required by managed Awtarchy features are installed automatically and are kept separate from optional package choices.

After installation, use:

```bash
awtarchy
```

Ly is optional. From a TTY, use `hypr`, `sway`, or `umbriel` for an installed
Awtarchy compositor. Awtarchy creates a
user-local `~/.local/bin/sway` entry only when installing Sway. With no
arguments from a TTY, it launches the same Sway session as Ly; native
`/usr/bin/sway` is never replaced, and Sway CLI arguments still use its
original executable. The login greeting lists available compositor commands.
For a custom login shell, keep `~/.local/bin` before `/usr/bin` in `PATH`.


The installed maintenance command lives at `~/.local/bin/awtarchy`.

## Preview before installing

The dry-run path shows the installer questionnaire and planned work without applying system changes:

```bash
./awtarchy-install.sh --dry-run
```

## Running the installer again

On an existing **complete** Awtarchy installation, running the installer normally repairs/refreshes the installed maintenance command and runtime without intentionally performing a full reinstall or replacing release-managed configuration. If the command exists but the desktop is incomplete, the installer reports an error rather than claiming the desktop was successfully installed. It does not silently overwrite partially installed or personalized configuration.

The selected compositor, Quickshell and Foot are mandatory desktop dependencies even when additional Arch repository packages are unchecked. A failed required or selected Arch package install, or missing required managed desktop configuration, stops the installer instead of reporting success. If a prior install was interrupted, use the full reinstall path only when that is actually intended:

```bash
sudo ./awtarchy-install.sh --reinstall
```

For normal Awtarchy upgrades, do not rerun the installer. Use the maintenance command documented in [UPDATING.md](UPDATING.md).
