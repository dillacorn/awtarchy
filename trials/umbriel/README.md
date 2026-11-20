# Awtarchy experimental Umbriel / Quickshell session

**Branch:** `feature/umbriel-quickshell-trial`. This is an isolated, unpublished
hardware experiment, not a stable Awtarchy release. Existing Hyprland, Sway,
Mango, KWin and Quickshell settings are not overwritten, and your installed
Awtarchy update/reset state is not modified.

## Installation

Run the checkout's `local/bin/awtarchy compositor` with
`AWTARCHY_UMBRIEL_TRIAL_SOURCE` set to the absolute clean checkout path.
Choose **Install Umbriel**. This calls only `trials/umbriel/manage.sh`,
checks AUR and existing packages, allows the interactive `yay` build for
`umbriel-git`, requires the upstream package-owned `umbriel.desktop`
session, then validates the experimental TOML against the installed binary
before staging missing private configuration files.

The experiment uses upstream `start-umbriel` for Ly and TTY sessions.
**No new .desktop entry** is created. Umbriel's session remains separate from
the existing Awtarchy Sway/Hyprland sessions.

## Separate state

- User config: `~/.config/umbriel/config.toml` is created ONLY if absent;
  an existing independent Umbriel configuration is never modified.
- Experimental TOML: `~/.config/umbriel/awtarchy-trial/config.toml`.
- Rendered shell: `~/.config/quickshell/awtarchy-umbriel/`.
- Shell bootstrap/IPC: `~/.config/umbriel/awtarchy-trial/`.
- Ownership baseline: `~/.local/state/awtarchy/umbriel-trial-baseline.json`.
- Existing Awtarchy Quickshell appearance preferences are read by the shell
  renderer; do not assume all compositor-specific controls are portable.

All installed Awtarchy compositor profiles are updated together through the
normal **Update configs** workflow. The existing **Review config changes**
action previews Sway and Umbriel files without changing them. Sway already
used this path; Umbriel now uses the same immutable release/git-testing source
with its own checksum baseline.

Updates replace only files matching their exact prior Umbriel managed checksum,
backing up changed files. Modified or unknown files are preserved. No package,
driver, compositor or session is removed during a config update. An installed
Umbriel package alone does not authorize Awtarchy to adopt personal config files;
the Awtarchy baseline must already exist.

The compositor menu has Install / Remove entries, not separate Update buttons.
**Remove Umbriel** removes only the selected package after checking another
supported compositor is installed and Umbriel is not running. Personal config,
the Awtarchy Quickshell profile, and the separate Umbriel portal remain intact.

**Release boundary:** a stable Update configs operation uses published release
sources, not this unpublished PR. Until a release containing this code exists,
the currently installed Awtarchy updater cannot deliver these Umbriel changes.
Running a git-testing update to this branch would also update the common
Hyprland Awtarchy files and change the user's current MangoWM test state;
do not present that as a safe Umbriel-only update.

## Initial supported scope

- A private rendering of the existing Awtarchy Quickshell UI, using the
  existing Sway layer-shell conversion as an input.
- Independent Umbriel workspace/window/output queries, using the real Umbriel
  JSON IPC instead of Sway's IPC or Hyprland Lua.
- Umbriel native session, simplified compositor menu, Foot, Fuzzel, basic
  workspace/window bindings, Quickshell launcher/power menu/notifications and
  PipeWire/audio surfaces are prepared for live testing.
- No automatic GPU-specific flags, output configuration migration, changes
  to NVIDIA drivers, or guessed VRR/tearing state.

## Known experimental limitations

This is **not** full Quickshell parity. Some existing Awtarchy shell helpers
still expect Sway/Hyprland-specific operations (capture, theme/window-rule
updates, lock capture, monitor editing, DDC/built-in brightness integration,
input modes, advanced positioning and utility toggles). Initial implementation
must prove shell startup first; unsupported actions should report errors or be
disabled, not claim to have changed another compositor.

For screen sharing use Umbriel's actual
`xdg-desktop-portal-umbriel` backend when packaged and tested; do not reuse
Sway's `xdg-desktop-portal-wlr` picker assumptions. The portal is **not**
automatically installed until its package is verified.

Upstream supports opt-in fullscreen VRR, tearing, direct scanout and HDR but
their actual availability depends on driver, monitor, client and rendering
path. Check `umbriel outputs --json`, `umbriel tearing`, and game behavior.
Do not infer results from accepted TOML keys.

References:
- https://github.com/noctalia-dev/umbriel
- https://docs.noctalia.dev/umbriel/
- https://aur.archlinux.org/packages/umbriel-git

## Abort/rollback

The native `umbriel.desktop` is package-owned. To stop using the trial, choose
Hyprland or Sway at the next login. Private Umbriel files and any personal
settings remain intact; no automatic removal or hidden reset is performed.
The Awtarchy stable compositor manager continues operating independently.
