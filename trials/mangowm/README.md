# MangoWM migration trial

Branch: **MangoWM_Migration_Trial_Investigation**. Targeted Mango version: **0.18.5** (2026-11-04).

**Status: isolated gameplay/desktop trial, NOT a complete Awtarchy migration.**
Hyprland remains the supported desktop until the missing integration is ported.

## Managed-migration branch (under development)

The current branch also stages `config/mango/` and a separate
`~/.config/quickshell/awtarchy-mango/` through `awtarchy git`.
This is not the older Waybar smoke-test configuration below.
The managed updater also contains the **v4.1.5 preserved Default Applications**
repair, with its original migration tests. The Quickshell shell, initial
PolicyKit IPC handling, wallpaper restore, and guarded idle actions are
implemented but have **not** been verified in a real Mango desktop session.

The native Quickshell lockscreen and exact protected-idle behavior are still
unported: the managed Mango branch currently uses secure Swaylock as a
temporary fallback, and screen-sharing privacy rules are fixed to Awtarchy's
default-protected applications. The dynamic Screen Share Guard controls cannot
yet change those rules. **Do not depend on them for custom capture exemptions.**

Swayidle receives compositor-managed idle notifications. Mango's native idle
inhibitors can suppress callbacks before Awtarchy's selective guard runs;
behavior is not yet identical to Hyprland's ignore-inhibitor configuration.


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

Return to the Hyprland login session before restoring a stable Awtarchy release
with `awtarchy update`. A normal stable release update is **not** a way to
advance the Mango trial; it will select the stable release instead.

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
