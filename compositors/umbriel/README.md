# Umbriel in Awtarchy

[Umbriel](https://github.com/noctalia-dev/umbriel) is an optional Awtarchy compositor alongside Hyprland (default) and Sway.

## Install and start

Open `awtarchy compositor` and select **Install Umbriel**. Awtarchy installs the supported upstream `umbriel-git` package when needed, uses its native Ly session, and stages a dedicated Quickshell profile. It does not replace another compositor or its configuration.

From a local TTY, type `umbriel` with no arguments to enter the same upstream `start-umbriel` session. The user-local launcher delegates all non-TTY launches and arguments to `/usr/bin/umbriel`, so existing IPC commands retain their meaning. Ly remains optional.

## Managed paths

- `~/.config/umbriel/config.toml` includes `~/.config/umbriel/awtarchy/`.
- `~/.config/quickshell/awtarchy-umbriel/` holds the separate Quickshell shell.
- `~/.local/state/awtarchy/umbriel-managed-baseline.json` records managed hashes.

`awtarchy review` and `awtarchy update` include an installed managed Umbriel profile. Upgrades retain old `~/.config/umbriel/awtarchy-trial/` files as a fallback and adopt their checksum baseline. Personalized legacy files are copied only when safe; unknown Umbriel configurations are never silently overwritten.

## Differences

Umbriel has native window animations, multi-GPU support, VRR/tearing options and a distinct workspace/output API. Awtarchy maps the supported Hyprland shortcuts, sound preferences, themes, floating utilities, and Quickshell controls into Umbriel-native equivalents. Incompatible compositor features are documented in [COMPOSITOR_PARITY.md](../COMPOSITOR_PARITY.md).

Output changes made with `wdisplays` do not automatically save Awtarchy TOML workspace rules. Quickshell layer-shell flyouts are anchored to the bar and are not ordinary movable windows. GPU performance, sched-ext activation and sound playback can vary by host.

## Upstream

- [Umbriel source](https://github.com/noctalia-dev/umbriel)
- [Umbriel documentation](https://docs.noctalia.dev/umbriel/)
- [AUR umbriel-git](https://aur.archlinux.org/packages/umbriel-git)
