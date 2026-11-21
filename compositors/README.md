# Optional compositor implementations

This directory contains the Awtarchy-managed source files for alternative
Wayland compositors. These are optional components, not part of the default
Hyprland configuration.

- [Sway](sway/README.md): managed Sway configuration, Quickshell integration,
  session helpers, settings migration, and installer/updater support.
- [Umbriel](umbriel/README.md): maintained Umbriel TOML, Awtarchy Quickshell
  rendering, source-to-Umbriel configuration migration, and session tooling.

Awtarchy's default Hyprland source stays under `config/hypr/`, and the
shared Quickshell source remains under `config/quickshell/awtarchy/`.

**Repository paths are not installation paths.** User-owned compositor
configuration stays in its existing `~/.config/sway/`, `~/.config/umbriel/`,
and `~/.config/hypr/` locations. Older Sway `awtarchy-trial` paths remain supported. Umbriel uses
`~/.config/umbriel/awtarchy`, retaining older trial files as a fallback.

Do not install by copying this source tree manually. Use the Awtarchy
compositor manager so dependency, ownership, and preservation checks apply.
