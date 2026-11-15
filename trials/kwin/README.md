# KWin compositor investigation (not installable yet)

This is an **isolated, read-only investigation** for a minimal KWin Wayland
session in Awtarchy. Hyprland remains the default; the existing optional Sway
implementation and all of its configuration remain unchanged.

This directory deliberately has **no session launcher or package installer**.
KWin can launch without Plasma, but Awtarchy's existing Quickshell/IPC/lock/
workspace wiring cannot currently be reused unchanged. Do not advertise the
KWin profile in the compositor menu or create a Ly entry until a functioning,
safely removable profile has been built and tested.

## Why KWin

- Arch distributes `kwin` independently of `plasma-workspace`. KDE
  libraries and `kglobalacceld` are dependencies; the full Plasma desktop
  is not an unavoidable dependency.
- KWin has built-in Wayland/DRM and XWayland support and can launch a child
  session with `--exit-with-session`. LXQt uses standalone KWin as a supported
  Wayland compositor, providing a precedent without bundling Plasma.
- This does **not** prove a better NVIDIA gaming outcome than Hyprland.
  Direct scanout, VRR, HDR, tearing behavior and latency must be tested.

## Read-only host survey

From a checkout of this branch:

```bash
bash trials/kwin/preflight.sh
```

The script checks only local package metadata and existing configuration. It
does not install, remove, rewrite, enable, start or stop anything. It does not
need root. A missing optional package is a status, not a change request.

## KWin monitor inspection

KWin's `libkscreen` package provides `kscreen-doctor`, which can query
monitor resolution, refresh rate, scale and position without the Plasma
desktop shell. During a running KWin trial, this read-only summary is
available via:

```bash
python3 trials/kwin/monitor-info.py
```

This *does not* save or configure monitors and should not be confused with
Sway's `nwg-displays`. It reports an absent `enabled` JSON property as
unknown rather than claiming a virtual monitor is off.

## Package dependency preview (no installation)

On an Arch/CachyOS host, `bash trials/kwin/package-plan.sh` prints the
package transaction that pacman would resolve from the **current local sync
databases**. It does not refresh databases, install packages, or change the
default compositor. The preview refuses a transaction containing
`plasma-workspace`, `plasma-desktop`, or `plasma-meta`. It also
includes the tiny official `python-dbus-next` package required by the
trial's workspace-state bridge. The
staging/smoke scripts assume `kwin` and `foot` are already installed;
there is still no production installer or package remover in this branch.

## Standalone DRM smoke test (not the Awtarchy session)

For testers who **already have** the official `kwin`, `quickshell`,
`python-dbus-next` and `foot` packages,
`tty-smoke.sh` can open an isolated KWin instance and one Foot terminal from
an otherwise unused local TTY. It requires the explicit
`AWTARCHY_KWIN_SMOKE=yes` opt-in. It refuses root, terminal emulators, nested
Wayland/X11 sessions, and detected concurrently running Hyprland/Sway/KWin
processes. This is **not** a production desktop. It starts a minimal Quickshell trial bar.
It stages a private KWin script package and enables 10 numbered workspaces,
but intentionally disables the unverified lockscreen. Workspace shortcuts
must still be confirmed live on KWin; offline tests only simulate the API.
Do not leave sensitive content unattended. Closing Foot should cause KWin
to stop and return to the TTY; actual KWin/driver behavior needs testing.
Settings use a newly created private directory under
`~/.local/state/awtarchy/kwin-smoke.*`; no desktop sessions or global portal
preferences are installed or changed. A user D-Bus bus is still shared and
its effects must be observed, so do not use this concurrently with another
desktop session.

## Isolated Quickshell integration probe

The TTY smoke session launches a private Quickshell `PanelWindow` on every
monitor, with a clock, session label and per-monitor desktop activity. This is a *protocol and lifecycle*
probe, not a replacement for the Awtarchy bar. Its source is
`trials/kwin/shell.qml` and its generated destination remains inside the
temporary KWin `XDG_CONFIG_HOME`. Closing Foot terminates the child session
and its own Quickshell PID. Real Wayland layer-shell operation and correct
session teardown still require runtime testing.

A separate KWin script publishes desktop/occupancy snapshots over a
session-only D-Bus name (`org.awtarchy.KWinTrial1`) to a private Python
`python-dbus-next` receiver. The receiver rejects invalid/oversized state
and atomically writes a private JSON file watched by Quickshell `FileView`.
The service starts before KWin, writes a complete placeholder JSON file
before declaring readiness, and is terminated when the TTY smoke test ends.
CI includes a real isolated D-Bus roundtrip, not just a JSON validation
stub. No existing user service or Sway/Hyprland IPC is modified.

The private `kwinrc` also enables per-output virtual desktops,
focus-follows-mouse, and Alt+left/right pointer move/resize. This matches
supported current KWin configuration keys rather than invented options.

## Experimental shortcuts loaded by the TTY smoke test

The private KWin script package registers `Super+1..0`, `Super+Shift+1..0`,
`Super+[`, `Super+]`, `Super+H/J/K/L` (directional focus), `Super+Q` (close)
and `Super+Ctrl+F` (fullscreen). KWin's native Alt+Tab is left alone. The
bindings rely on KWin 6's documented scripting API; CI exercises API stubs,
**not** actual KGlobalAccel registration or input delivery. KWin's stock
`Super+Arrow` quick-tiling shortcuts are deliberately not overridden yet.
No attempt is made to pass off the stacking compositor as dynamically tiled.

## Experimental dynamic tiling

A second **trial-only** KWin script implements conservative dwindle-style
geometry with 9 px outer gaps and 6 px inner gaps. It uses KWin's actual
`workspace.clientArea` per output and per virtual desktop, and ignores
fullscreen windows, recognized games, utility windows, minimized windows and
always-on-top windows. A layout that cannot fit minimum tile sizes is left
untouched rather than placing windows offscreen. `Super+F` and `Alt+F`
toggle an ordinary window out of tiling, restoring its previous geometry;
toggling again retiles it. This is trial-only and its live KWin shortcuts
still need verification. This is not feature parity
with Hyprland's full dwindle layout: interactive split ratios, rearrangement,
scratchpads, and reliable fullscreen gaming still require live validation.

## Integration constraints

1. Keep Hyprland's `hyprland.lua`, Hyprland Quickshell profile and all Sway
   files untouched. Create KWin-specific files under a separate
   `~/.config/kwin/awtarchy/` namespace, not in `~/.config/kwinrc` until the
   update/restore model is proven. The KWin config ownership and launch-time
   selection mechanism require investigation before writes.
2. Use an independent KWin session (Ly and TTY), with explicit opt-in and
   verified exit/recovery. Never auto-start a second compositor inside an
   existing Wayland/X11 session. Don't use `dbus-run-session` over an existing
   user bus.
3. Keep all KWin-only XDG portal mappings session-specific. A KDE portal
   backend may be installed but must not become the selected Hyprland or Sway
   screencast backend. Validate actual PipeWire/OBS capture in each session.
4. Do not enable a KWin service globally, replace system default KDE/Qt
   settings, change XDG MIME handlers, overwrite a custom `kwinrc`, or run
   package removals based solely on dependency lists. Preserve the existing
   Awtarchy package ledger and its ownership policy.
5. Do not claim the existing Awtarchy Quickshell lockscreen is secure on KWin
   until the Wayland session-lock protocol, PAM confirmation, capture and
   failure paths are tested. Do not ship a session with an unverified lock.
6. A KWin window-management script and a dedicated Quickshell integration
   are needed. The KWin Scripting API supports window/workspace control and
   `registerShortcut` but is different from `hyprctl` and `swaymsg`.
7. Stock KWin is a stacking compositor. Awtarchy's auto-tiling, numbered
   workspace behavior, moving workspaces between monitors, floating utility
   rules, gaps, alt-drag, Alt+Tab, mouse modes, and shortcuts are **not**
   automatically present merely because KWin runs.

## Acceptance criteria before exposing an install option

- [ ] Arch dependency preview identifies the exact package transaction;
      no `plasma-workspace` or `plasma-meta` is installed by Awtarchy.
- [ ] Isolated and reversible install, ownership tracking and dry-run;
      remove only known Awtarchy-owned KWin-specific packages.
- [ ] Dedicated Ly/TTY session with recovery path and GPU-specific safety,
      no changes to existing Hyprland and Sway startup.
- [ ] KWin-native configuration/scripts for Awtarchy's normal bindings,
      workspace/navigation/floating/gap and window-mode expectations.
- [ ] Awtarchy KWin Quickshell profile with keyboard focus, bar, flyouts,
      notifications, quick settings, theme selection and per-monitor settings.
- [ ] Secure working lock, idle, screenshot, portals, OBS/screen-sharing and
      screenshare-guard fail-closed behavior.
- [ ] NVIDIA full-screen Proton/game testing: direct scanout, frame pacing,
      VRR, HDR, tearing, mixed-refresh monitor layout and input latency.
- [ ] Confirm Hyprland and Sway work after KWin installation and removal.
- [ ] Stable updater/review/backup behavior retains user KWin settings,
      including monitors and KWin-specific shortcuts.

## Sources

- KWin CLI: https://github.com/KDE/kwin/blob/master/src/main_wayland.cpp
- KWin scripting: https://develop.kde.org/docs/plasma/kwin/api/
- LXQt standalone KWin: https://github.com/lxqt/lxqt/wiki/Wayland-Session
- Arch package: https://archlinux.org/packages/extra/x86_64/kwin/

No package or user session is modified by this investigation.
