# MangoWM migration trial

Branch: **MangoWM_Migration_Trial_Investigation**. Targeted Mango version: **0.18.5** (2026-11-04).

**Status: branch-only first-login trial candidate, not a stable release.**
CI checks Mango's configuration parser, generated QML, key-mode persistence,
PolicyKit simulation, and managed rollback safeguards. A live Mango login,
actual display/Proton behavior, and a full stable-release restoration remain
unverified. Hyprland remains installed and supported.

## Managed-migration branch (under development)

Once the managed configuration is installed and **Mango** is selected in the
login manager, run the read-only startup diagnostic:

~~~bash
bash "$HOME/awtarchy-mango-trial/trials/mangowm/diagnose.sh"
~~~

The diagnostic reports only PASS/MISSING/INACTIVE conditions, not process
command lines, clipboard contents, open-window titles or authentication data.
A clean diagnostic does not prove locking, game rendering, video capture or
power transitions. Return to the **Hyprland** login session to abandon a
failed Mango session; do not remove your Hyprland configuration.


The current branch also stages `config/mango/` and a separate
`~/.config/quickshell/awtarchy-mango/` through `awtarchy git`.
This is not the older Waybar smoke-test configuration below.
The managed updater also contains the **v4.1.5 preserved Default Applications**
repair, with its original migration tests. The Quickshell shell, initial
PolicyKit IPC handling, wallpaper restore, and guarded idle actions are
implemented but have **not** been verified in a real Mango desktop session.

Managed Mango implementation in this branch:
- Isolated Mango Quickshell profile, bridge, bar, launcher, clipboard,
  notifications, focus/positioning helpers, persisted UI preferences and theme.
- Original Quickshell session-lock UI is attempted through Mango's native
  Wayland session-lock protocol. A secure Swaylock fallback remains; the
  Hyprland-only frozen-frame transition is intentionally disabled in Mango.
- ALT/SUPER left-drag retains the window's actual tiled size instead of
  Mango's default 300x300 drag thumbnail. Pointer warping on floating-window
  corner resize is disabled; tiled drop/rearrangement remains available.
  These are supported Mango 0.18.5 settings, not a promise of pixel-identical
  Hyprland drag/drop visuals. Validate the feel when returning to Mango.
- The existing trusted PolicyKit terminal agent has a Mango window-ID backend
  with regression tests; actual authentication must still be tested live.
- The original 60/120/180/240/540/14400-second idle cadence is wired through
  Swayidle and Awtarchy guards. Mango's compositor-native idle inhibitors can
  suppress callbacks before Awtarchy's selective logic sees them.
- Mango Quick Settings shares Awtarchy's brightness, scheduler, wallpaper,
  and Quickshell bar state. Mango display inventory is sourced from `mmsg`.
  The `noalt`, `mouse` and `vm` key modes now switch through Mango's native
  `setkeymode` dispatcher with independent persistence. Mouse mode requires
  SUPER for drag/resize: Mango does not allow unmodified primary-button drags
  in ordinary client windows. Night-light and vibrance remain unsupported and
  report an explicit error instead of pretending to work.
- Default Applications (including v4.1.5 preserved-configuration repair),
  Qalc and other floating utility toggles have native Mango IPC backends.
- The existing static screen-sharing privacy rules apply by default. Mango's
  Screen Share Guard panel is intentionally **read-only**: it does not expose
  toggles that cannot affect Mango capture shielding. Verify real capture
  behavior before sharing sensitive content.
- The Mango keybinding profile includes the restored ALT+SHIFT+RETURN,
  Default Applications, AwtWall picker, native DDC brightness, color picker,
  exact-window capture, workspace keys, VM-mode mouse/QR actions, and
  relative resize dispatchers. Native Mango input watchers replace the old
  750 ms Quickshell workspace poll.
- `SUPER+CTRL+M` opens **wdisplays** (Wayland-native display settings) in
  Mango instead of Hyprmoncfg. Monitor positioning and refresh are persisted
  through an opt-in `monitors-local.conf`, not by guessing global defaults.
- Mango's AwtWall picker runs with a compatible swww/awww backend; the
  all-display random shortcuts also use this backend. AwtWall's current-monitor
  random shortcut still depends on upstream non-Mango focus detection and
  needs a native upstream adapter to be equivalent.
- GPU package management and Hyprland configuration stay intact for reversal.

Live blockers include verifying shell focus and window behavior, real
PolicyKit authentication, screen sharing, multi-monitor scaling, Mango idle
inhibition, suspend/lock/unlock, and the stable-release restoration path.
Do not rely on static CI to prove any of these. Do not uninstall Hyprland.


Do **not** run `trials/mangowm/setup.sh --install` after applying the
managed branch: that old script deliberately refuses to overwrite the
new `~/.config/mango/config.conf`. Keep Hyprland installed so returning
to the **Hyprland** login session remains possible.

### Controlled first-login trial

Before installing the branch, preserve a checkout of the same migration source
for diagnostics and later stable restoration. Run these commands as your
**normal user in Hyprland**, not through sudo. Do not run the older standalone
`setup.sh --install` after a managed update.

~~~bash
git clone --branch MangoWM_Migration_Trial_Investigation --single-branch \
  https://github.com/dillacorn/awtarchy.git \
  "$HOME/awtarchy-mango-trial"
awtarchy git review --branch MangoWM_Migration_Trial_Investigation
awtarchy git update --branch MangoWM_Migration_Trial_Investigation
~~~

The managed Git update selects the exact remote branch revision. If it advances
after cloning, check the recorded revision in
`~/.local/state/awtarchy/git-testing` and use a clean checkout at that **exact**
revision for stable recovery. Do not force-reset a checkout containing changes.

After approval and successful installation, check that the Arch package
provides its standard session entry before attempting to log into Mango:

~~~bash
pacman -Q mangowm
pacman -Qkk mangowm
test -f /usr/share/wayland-sessions/mango.desktop
~~~

**Ly does not refresh its session menu automatically.** If the Mango package
and session entry are present but Ly does not offer Mango after logging out,
**reboot** to restart Ly and refresh its cached list. Do not run
`systemctl restart ly` from an active Hyprland session: doing so can terminate
the graphical session. If Mango is still absent, inspect Ly's configured
`waylandsessions` directory in `/etc/ly/config.ini` or `/etc/ly/config.lua`,
rather than creating an unowned duplicate desktop entry.

After restarting the display manager, select the packaged **Mango** session
at login. Within Mango:

~~~bash
bash "$HOME/awtarchy-mango-trial/trials/mangowm/diagnose.sh"
mmsg get keymode
mmsg get all-monitors
mango -c "$HOME/.config/mango/config.conf" -p
~~~

A zero-error diagnostic covers only startup probes. It does not prove real
window/focus geometry, gaming, secure locking, or capture. Before depending
on the trial, inspect the Quickshell bar, flyouts, notifications, launcher,
clipboard, retained preferences, Foot/PolicyKit authentication, multiple
monitors, brightness, mouse and VM key modes, and wallpaper. Then test
lock/unlock and a deliberate suspend/resume with the Hyprland login fallback
available. Screen sharing must be tested with a **non-sensitive** sample
window before relying on its shielding. Finally compare a known Proton game
against the same game settings under Hyprland (VRR, cursor confinement,
fullscreen, alt-tab, frametimes and Gamescope).

Toggle key modes with SUPER+ALT+N (noalt), SUPER+ALT+M (mouse), or
SUPER+ALT+V (VM). Repeating the active toggle returns to default.
If a mode becomes inconvenient, use the Mango IPC recovery command:

~~~bash
mmsg dispatch setkeymode,default
~~~

Do not assume feature parity for the unsupported Mango night-light, vibrance,
dynamic capture rules, Hyprmoncfg, Hyprland screen shaders, or window transfer
features. Preserve Hyprland as the working rollback session.

### Optional gaming-PC monitor profile

The generic installer does not assume your display connectors or preferences.
Once the managed Mango branch is installed, this trial provides an explicit
profile for the **DP-3 ViewSonic 1080p/240 Hz above the DP-1 BenQ
1080p/400 Hz** configuration, scale 1, VRR off. XWayland coordinates are
normalized to nonnegative positions, with the BenQ as the X11 primary.

A conservative alternative is to preview and import literal monitor rules
from your **installed** Hyprland Lua configuration:

~~~bash
python3 "$HOME/awtarchy-mango-next/config/mango/scripts/import-hypr-monitors.py" \
  --primary DP-1

# Only after reviewing the preview; refuses an existing destination:
python3 "$HOME/awtarchy-mango-next/config/mango/scripts/import-hypr-monitors.py" \
  --primary DP-1 --apply
~~~

Do not install both profiles, overwrite an existing
`~/.config/mango/monitors-local.conf`, or change the monitor geometry while
testing a game. The saved Mango profile is separate from the original
Hyprland settings. Confirm actual refresh and output layout with `wlr-randr`
after the next Mango login.

### Still non-equivalent

Mango has no drop-in equivalents for the original Hyprland shader zoom,
vibrance shader, Hyprbars, workspace-mix implementation, dynamic screen-share
privacy toggles, night-light controls, or whole-workspace monitor-transfer
shortcuts. Those are intentionally not replaced with similarly named but
different dispatchers. AwtWall's `--random-current` focus detection and
Hyprland's fast Power Menu submap also remain runtime verification items.
Do not call this 1:1 behavior until those are addressed or accepted as
Mango-specific limitations.

### Return to the recorded stable release

1. Log out of Mango and select **Hyprland** at the login manager. This is the
   immediate recovery path even if the Mango shell fails to load. Do not remove
   Hyprland or its configuration.
2. In a **clean Git checkout of the exact revision installed by**
   `awtarchy git update`, use the following safe review first. The checkout must
   match the `revision=` recorded in `~/.local/state/awtarchy/git-testing`.
3. Review the managed-file plan, then run the interactive restore. It uses the
   recorded `stable_release=` (not an assumed latest release) and the **trial's
   Mango-aware runtime**, because the current stable/main updater does not
   recognize the Mango-managed baseline namespace.

~~~bash
bash "$HOME/awtarchy-mango-trial/trials/mangowm/restore-stable.sh" --review
bash "$HOME/awtarchy-mango-trial/trials/mangowm/restore-stable.sh" --restore
~~~

The helper refuses execution outside a responsive Hyprland session, if the
checkout has modifications, if HEAD differs from the installed trial revision,
or if the recorded stable release is inconsistent. It does not accept a
caller-supplied release tag. The normal Awtarchy updater can be used again
**after** the stable managed baseline has been restored successfully.

This workflow has mock/static coverage but **has not been proven in a live
Mango-to-Hyprland round trip**. A stable config restore does not necessarily
remove all trial-installed packages or undo system-level package upgrades.
The separate Quickshell state remains user-owned and is not discarded.

### Older standalone smoke test

The following separate test path intentionally uses Waybar, Fuzzel and Mako.
It is maintained only for regression comparisons, not for the managed migration.

## Setup on Arch

Checkout the named branch, then install the trial's new dependencies:

~~~bash
sudo pacman -S --needed mangowm waybar fuzzel mako swaybg swayidle swaylock xdg-desktop-portal-wlr xdg-desktop-portal-gtk grim slurp wlr-randr jq
bash trials/mangowm/setup.sh --check
bash trials/mangowm/setup.sh --install
~~~

The setup script does not invoke pacman, remove packages, overwrite a differing
Mango configuration, change your display manager default or modify Hyprland.
It checks conflicts before writing to ~/.config/mango and
~/.config/xdg-desktop-portal/mango-portals.conf.

Log out and choose the packaged **Mango** desktop session in the login manager.
Return to **Hyprland** in the login manager if this trial is unusable.

## Validate inside Mango

~~~bash
mmsg get version
mmsg get all-monitors
mmsg get all-tags
mmsg get all-clients
mango -c ~/.config/mango/config.conf -p
~~~

Compare the *same* Proton game with Hyprland using the same monitor and game
settings. Inspect: visual freezes, audio continuing, workspace recovery, mouse
confinement, input latency, frametimes, alt-tab, screen capture, sharing,
multi-monitor focus, VRR, suspend/resume and reconnect.

Stock Waybar 0.15 does not include mango/* modules; this trial uses a
portable custom module instead. No monitor rules were guessed. Use mmsg get all-monitors to identify outputs
before setting resolution, refresh rate, location, scaling and VRR.

## Current trial features

- Native Mango bindings (ALT/SUPER), basic tiling/floating/fullscreen, special
  tag, 10 tags, dim-free rendering, disabled cosmetic effects.
- A minimal stock Arch Waybar using an mmsg/jq tag adapter, Fuzzel, Mako.
- Swaybg, Swayidle/Swaylock, Mango's ScreenCast/Screenshot portal, screenshots,
  power menu; existing Awtarchy standalone default-app, Qalc, Yazi, Btop tools.
- Mango fullscreen-only tearing (allow_tearing=2), syncobj enabled. This is
  **not** Hyprland direct_scanout=2 (auto).

## Not yet migrated in the older standalone smoke test

- Main Awtarchy Quickshell bar/flyouts, launcher, clipboard, notifications,
  quick settings, theme picker, screenshare guard and related custom scripts.
  They import Quickshell.Hyprland or call hyprctl directly.
- Awtarchy Quickshell lockscreen (temporary Swaylock substitute), custom
  PolicyKit terminal agent (depends on Hyprland window control), custom idle
  policy, desktop updater-managed configuration.
- Monitor profiles/Hyprmoncfg, custom zoom, workspace mixer, vibrance shader,
  Hyprbars, wallpaper restoration/picker and night-light controls.
- Screen capture of a specific window and historical clipboard controls.

**Do not delete Hyprland packages or switch Awtarchy's default desktop based on
this trial.** GUI admin authentication cannot be considered functional until
the PolicyKit TUI is ported and tested. Steam/Proton/Gamescope and unrelated
applications can continue to be shared between the two sessions.

Production package replacement map (not performed here):

| Hyprland-specific | Mango alternative |
|---|---|
| hyprland | mangowm (mango, mmsg) |
| xdg-desktop-portal-hyprland | xdg-desktop-portal-wlr |
| hypridle | swayidle |
| hyprsunset | wlsunset (not configured yet) |
| hyprpaper | swaybg (temporary) |
| hyprbars/hyprpm | Mango decorations or separate title bars |
| hyprmoncfg | Mango monitor rules and wlr-randr (partial) |
| hyprpicker | Needs independent Wayland color-picker validation |
| Hyprland Lua and hyprctl scripts | Mango config and mmsg rewrites (incomplete) |

Upstream reference:
https://mangowm.github.io/docs/
https://github.com/mangowm/mango/releases/tag/0.18.5
https://mangowm.github.io/docs/visuals/status-bar/
https://mangowm.github.io/docs/configuration/xdg-portals/
