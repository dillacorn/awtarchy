# Awtarchy experimental Umbriel / Quickshell session

**Branch:** `feature/umbriel-quickshell-trial`. This is an isolated, unpublished
hardware experiment, not a stable Awtarchy release. Existing Hyprland, Sway,
Mango, KWin and Quickshell settings are not overwritten, and your installed
Awtarchy update/reset state is not modified.

## Installation

Run the checkout's `local/bin/awtarchy compositor` with
`AWTARCHY_UMBRIEL_TRIAL_SOURCE` set to the absolute clean checkout path.
Choose **Install Umbriel**. This calls only `compositors/umbriel/manage.sh`,
checks AUR and existing packages, allows the interactive `yay` build for
`umbriel-git`, requires the upstream package-owned `umbriel.desktop`
session, then validates the experimental TOML against the installed binary
before staging missing private configuration files.

The experiment uses upstream `start-umbriel` for Ly and TTY sessions.
**No new .desktop entry** is created. Umbriel's session remains separate from
the existing Awtarchy Sway/Hyprland sessions.

## Ly session verification

The AUR package normally installs one package-owned
`/usr/share/wayland-sessions/umbriel.desktop`, launching `start-umbriel`.
The installer confirms that file exists and is owned by a package, but
**cannot establish that a running Ly process has refreshed its session menu**.
Ly enumerates session directories when the interface starts. If Ly started
before the Umbriel package was installed, reboot before testing its list;
never restart Ly from an active graphical session as a shortcut.

For missing entries, run the read-only `compositors/umbriel/diagnose-session.sh`
script. It checks installed packages, the desktop entry and ownership, Ly's
configured Wayland session paths, and Ly's service start time. Do not create
a duplicate .desktop entry to work around a stale list.

The **normal** installed `awtarchy` command uses `main` and does not
automatically acquire this experimental branch's compositor menu. Test the
checkout using `AWTARCHY_UMBRIEL_TRIAL_SOURCE` and its
`local/bin/awtarchy`. Only a separately authorized merge and appropriate
command update can make the normal menu include Umbriel. The experiment
does not replace or reset the user's current MangoWM configuration.

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
- A managed `awtarchy-trial/migrated.toml` include imports representable
  monitor settings and keybinds from saved Hyprland/Sway configuration without
  executing source scripts. It loads after Awtarchy's Umbriel defaults.
- On Hyprland, saved `hyprmoncfg-monitors.lua` takes precedence; if absent,
  unique matching `hyprmoncfg/profiles/*.json` layouts are supported.
  Disconnected outputs, ambiguous layouts, dynamic rules, and unsupported
  compositor-only shortcuts are skipped instead of guessed.
- The importer prefers the currently running supported source compositor, then
  a pre-existing last-compositor marker. If neither exists, Hyprland is a
  *fallback*, not evidence it was last used. Set
  `AWTARCHY_MIGRATE_FROM=sway` (or `hyprland`) explicitly if needed.
- Existing NVIDIA drivers and kernel configuration are never changed.
  Output-level tearing and direct scanout are enabled for eligible fullscreen
  games. The importer uses fullscreen VRR only on displays where Umbriel
  reports adaptive-sync support, while retaining explicit source policies.
  These options permit lower latency but do not guarantee an asynchronous
  flip, direct scanout, or active VRR in every game.

## Retesting an installed Umbriel trial

Use the existing `~/awtarchy-umbriel-trial` checkout. Fast-forward the
experimental branch, then run `compositors/umbriel/sync.py preview --repo
<checkout>` before `apply`. The managed config, Quickshell assets and
`migrated.toml` are installed only when missing or still matching the
Awtarchy checksum baseline; personalized files are never overwritten.

Prefer applying while signed into Hyprland, then log into Umbriel to verify
physical monitor modes, positioning, and shortcuts. The importer reports the
selected source and number of verified displays/shortcuts. A report of
`displays=0` is a failed display migration, not proof of success. Do not
replace custom Umbriel layout files to force an import.

## Appearance, flyouts, and display management

- Default Awtarchy Umbriel windows now request a 1px border, square corners,
  and an animation profile tuned toward the current Hyprland defaults.
  This is a *translation*, not a promise that two different compositors
  implement identical animations.
- `ThemePicker` uses Umbriel's dedicated `theme-apply.sh`, updates
  `~/.config/quickshell/awtarchy-umbriel/theme.json`, and writes a
  private `theme.toml` include with Umbriel's native focused/unfocused border
  colors. Theme names with non-ASCII letters are supported. Hyprland and Sway
  compositor files remain unchanged.
- The Sway and Umbriel rendered Quickshell flyout managers close competing
  flyouts immediately when another is claimed. The newly opened theme
  picker is exempt from its own close signal.
- Umbriel wallpaper shortcuts, Quick Settings, and login restoration use a
  private launcher that prefers the packaged `/usr/bin/awtwall` over any older
  `~/.local/bin/awtwall`. The user-local executable is never modified;
  other compositor launch behavior is unchanged.
- `Super+Ctrl+M` opens **wdisplays**, an upstream-supported wlr-output-
  management GUI. It manages connected displays, modes, scale and arrangement;
  it is **not** a workspace editor. Live changes made in wdisplays are not
  automatically written into Awtarchy's `migrated.toml` and may not survive
  a compositor restart. Do not misrepresent them as saved.
- Umbriel and Sway use layer-shell panels to avoid tiling and preserve their
  output-local positions. Resizing the layer-shell surface during an active
  pointer grab can break the gesture. The current ALT+right drag previews a
  size and commits once on release; it is not Hyprland's continuous floating-
  window resize. Right/bottom edge handling is corrected so inward dragging
  enlarges the panel.

## Native window mouse controls and global workspace identity

Umbriel has one compositor-owned mouse-drag modifier (`general.mod_key`).
Awtarchy sets it to **Alt**: Alt+left-drag moves windows and Alt+right-drag
resizes them. All existing Super keyboard shortcuts are expressed with explicit
`Super+` chords, including migrated bindings; the native Super+mouse grab is
therefore replaced rather than retained as a second drag modifier.

Awtarchy uses ten globally named workspaces, initially on the selected home
output. Other monitors use dynamic local workspaces and should not duplicate
the global names. `Alt+1` and `Super+1` target the named workspace 1
irrespective of its current output; transferring a named workspace preserves
its identity. Workspace layout changes from the prior output-local 10/10 model
should be applied from another compositor before beginning a new Umbriel
session, not live-reloaded with open windows.

## Known experimental limitations

This is **not** full Quickshell parity. Some existing Awtarchy shell helpers
still expect Sway/Hyprland-specific operations (capture, dynamic window-rule
updates, lock capture, persistent monitor editing, DDC/built-in brightness integration,
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
