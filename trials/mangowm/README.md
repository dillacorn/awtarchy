# MangoWM migration trial

Branch: **MangoWM_Migration_Trial_Investigation**. Targeted Mango version: **0.18.5** (2026-11-04).

**Status: actively developed, branch-only managed desktop migration.**
CI now checks Mango's real configuration parser and the generated Qt QML syntax.
Neither a live Mango login nor reversible stable-release restoration is proven.
Hyprland remains installed and supported.

## Managed-migration branch (under development)

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
- The existing trusted PolicyKit terminal agent has a Mango window-ID backend
  with regression tests; actual authentication must still be tested live.
- The original 60/120/180/240/540/14400-second idle cadence is wired through
  Swayidle and Awtarchy guards. Mango's compositor-native idle inhibitors can
  suppress callbacks before Awtarchy's selective logic sees them.
- Mango Quick Settings shares Awtarchy's brightness, scheduler, wallpaper,
  and Quickshell bar state. Mango display inventory is sourced from `mmsg`.
  Night-light, vibrance and non-default key mode actions currently fail with
  an explicit error rather than pretending to change settings.
- Default Applications (including v4.1.5 preserved-configuration repair),
  Qalc and other floating utility toggles have native Mango IPC backends.
- The existing static screen-sharing privacy rules apply by default. The
  dynamic Screen Share Guard controls **do not** update those rules.
- GPU package management and Hyprland configuration stay intact for reversal.

Live blockers include verifying shell focus and window behavior, real
PolicyKit authentication, screen sharing, multi-monitor scaling, Mango idle
inhibition, suspend/lock/unlock, and the stable-release restoration path.
Do not rely on static CI to prove any of these. Do not uninstall Hyprland.


Do **not** run `trials/mangowm/setup.sh --install` after applying the
managed branch: that old script deliberately refuses to overwrite the
new `~/.config/mango/config.conf`. Keep Hyprland installed so returning
to the **Hyprland** login session remains possible.

Static review from the installed Awtarchy command:

~~~bash
awtarchy git review --branch MangoWM_Migration_Trial_Investigation
~~~

Managed application (only after the migration has passed its readiness checks):

~~~bash
awtarchy git update --branch MangoWM_Migration_Trial_Investigation
~~~

To reverse the *running desktop*, select **Hyprland** from the login manager.
This does not require deleting Mango packages or modifying the saved Quickshell
state. A stable `awtarchy update` selects the published release, **not** the
unreleased Mango branch. Full managed-file cleanup/restoration after a Mango
trial is **not yet verified**; do not assume a stable update reverses every
file or package change.

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
