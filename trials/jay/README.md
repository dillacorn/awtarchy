# Awtarchy JayWM migration trial

Branch: `JayWM_Migration_Trial_Investigation` (forked from `main` at `da4462d0c488e7949ddc8168f4b4dddb1c9e9fe1`).

This branch stages a **separate Jay compositor session** to investigate fullscreen tearing, numerical workspaces, multi-monitor gaming and migration parity. It is **not yet a complete Quickshell migration**. It does not overwrite Hyprland or the stable Awtarchy runtime.

## Install from the existing Hyprland session

```bash
git clone --branch JayWM_Migration_Trial_Investigation --single-branch https://github.com/dillacorn/awtarchy.git "$HOME/awtarchy-jay-trial"
cd "$HOME/awtarchy-jay-trial"
bash tests/test-jay-trial.sh
python3 tests/test-jay-monitor-profile.py
bash trials/jay/setup.sh --packages
bash trials/jay/setup.sh --check
bash trials/jay/setup.sh --install
```

The `--packages` step installs the `jay` AUR package through **`aur-scan install jay --noconfirm`**; its official supporting packages use pacman. The scripts don't remove anything or change the Awtarchy managed package ledger. `--check` is read-only and refuses any configuration collision; `--install` stages files only if absent/byte-identical and creates a separate `Jay (Awtarchy Trial)` Wayland session in Ly.

**Reboot, then choose Jay (Awtarchy Trial) at Ly.** Don't restart Ly from an active graphical session. If it fails, return to **Hyprland** at Ly. Your Hyprland files, kernel and graphics drivers are unchanged.

## Test Jay after logging in

```bash
bash "$HOME/awtarchy-jay-trial/trials/jay/diagnose.sh"
jay randr show --modes
```

The native Jay status bar shows true workspaces, not tags. ALT/SUPER + 1–0 selects 1–10; SHIFT moves the focused window; ALT/SUPER + arrows or HJKL focuses; add SHIFT to move; ALT/SUPER+CTRL+SHIFT+Left/Right moves the **whole workspace** between monitors. SUPER+Return opens Foot, SUPER+R or ALT+P opens Fuzzel, SUPER+CTRL+L locks, ALT+C opens the Jay control center, ALT+SHIFT+R reloads.

### Persist monitor modes, positions and refresh rates

The Jay control-center display editor and `jay randr` modifications do **not** persist automatically across logins. After confirming actual connector names and supported refresh rates with `jay randr show --modes`, use:

```bash
python3 "$HOME/awtarchy-jay-trial/trials/jay/monitor-profile.py" --list
python3 "$HOME/awtarchy-jay-trial/trials/jay/monitor-profile.py" --set DP-1 1920x1080@240 0x0 1.0
```

**The DP-1 and 240 Hz values above are examples, not detected hardware settings.** The profile writer preserves all unrelated Jay config, validates the resulting TOML, and creates a timestamped backup before each write. It refuses symlinks, unsupported values, custom output declarations and unknown profile content. Verify settings immediately and after another login.

### Fullscreen tearing and gaming

The trial defaults to `tearing.mode = "variant2"` (a single fullscreen application) and `vrr.mode = "variant1"` (fullscreen VRR). To temporarily permit tearing unconditionally on one identified output:

```bash
jay randr output DP-1 tearing set-mode always
```

Only use a verified actual connector. Compare the same native/Proton game, same refresh rate, same frame cap and equivalent VRR setting. SUPER+CTRL+ALT+F12 toggles the compositor/direct-scanout indicator. A configuration accepting a tearing mode is *not* confirmation of asynchronous presentation on your AMD GPU.

Jay's native ScreenCast and RemoteDesktop portals need an installed `/usr/share/xdg-desktop-portal/portals/jay.portal` descriptor, PipeWire, and a working `xdg-desktop-portal` session. Confirm a real screen share; static files cannot establish capture works.

### Explicit parity limitations / blockers

The current independent session provides: native Jay workspace bar, Fuzzel launcher, Mako notifications, Swaylock, AWWW/AwtWall wallpaper restore, basic clipboard capture, core window/workspace bindings, audio bindings, screenshots, and the native Jay display editor.

**Not implemented and not represented as working:** Awtarchy's Hyprland-dependent Quickshell bar, flyouts, launcher, quick settings, animation and lockscreen; Awtarchy terminal PolicyKit backend (Jay has an isolated LXQt fallback); protected idle/suspend logic; dynamic privacy Screen Share Guard; digital vibrance shader; workspace mixing; scratchpad/submaps; floating utility toggles; active-window UI; Sunshine integration; native Quickshell display/wallpaper settings and per-monitor state. These require Jay-specific adapters. GPU/render latency, screen sharing, locking and high-refresh multi-monitor setup need testing in a real Jay session.

Do **not** use `awtarchy git update` to install this test. Its stage is deliberately separate from Awtarchy's stable updater/backup baseline until the desktop migration path has been ported and validated.

## Abandon trial

Log out of Jay and choose Hyprland from Ly. Leave installed Jay test files alone until you've decided whether to continue; no package removal, overwrite or stable release rollback is required.

References: [Jay project](https://github.com/mahkoh/jay), [official Jay output configuration](https://github.com/mahkoh/jay/blob/master/book/src/configuration/outputs.md).
