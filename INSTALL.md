# Installing Awtarchy

Awtarchy is an Arch Linux desktop overlay, not a distribution or a base OS installer. **Vanilla Arch Linux (recommended) and CachyOS are supported installation bases.**

## Install a supported base first

For a new machine:

1. **Recommended:** install [vanilla Arch Linux](https://archlinux.org/download/) using `archinstall` with the **Minimal** profile, or follow the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) for manual installation.
2. **Alternatively:** install [CachyOS](https://cachyos.org/) using its official installer. A minimal setup is preferable, but an existing working CachyOS desktop can be used.
3. Boot into your installed system and log in before running Awtarchy.

Awtarchy overlays its own Hyprland/Quickshell desktop and managed configuration. CachyOS-specific safeguards preserve existing driver/network/display-manager state where practical, but installed desktop configuration may still be updated by Awtarchy. See [CachyOS compatibility notes](docs/cachyos-compatibility.md).

## Install Awtarchy

Install Git, clone the repository, and run the installer:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

The installer collects the relevant hardware/package choices before applying the overlay. Dependencies required by managed Awtarchy features are installed automatically and are kept separate from optional package choices.

After installation, use:

```bash
awtarchy
```

The installed maintenance command lives at `~/.local/bin/awtarchy`.

## Preview before installing

The dry-run path shows the installer questionnaire and planned work without applying system changes:

```bash
./awtarchy-install.sh --dry-run
```

## Running the installer again

On an existing Awtarchy installation, running the installer normally repairs/refreshes the installed maintenance command and runtime without intentionally performing a full reinstall or replacing release-managed configuration.

Use the full reinstall path only when that is actually intended:

```bash
sudo ./awtarchy-install.sh --reinstall
```

For normal Awtarchy upgrades, do not rerun the installer. Use the maintenance command documented in [UPDATING.md](UPDATING.md).
