# Sway (Awtarchy Trial): extended first-login checklist

This is an experimental standard-Sway session. It does **not** replace Hyprland.
The checklist includes features implemented in source, behaviors requiring a live
test, and known unsupported Hyprland-only capabilities.

Before testing: update the trial branch, use `awtarchy compositor` to **Review
Sway managed config changes** and then **Apply Sway managed updates**.
Preserve imported DP-1/DP-3 display modes and any customized Sway configuration.
A commit and static CI pass do not prove working Quickshell/Wayland behavior.

## 1. Session, display and input

- [ ] Ly lists both **Hyprland** and **Sway (Awtarchy Trial)**.
- [ ] Cursor is visible after login and remains visible over games and flyouts.
- [ ] DP-1 activates 1920×1080 at approximately 400.002 Hz.
- [ ] DP-3 activates 1920×1080 at approximately 239.761 Hz.
- [ ] Monitor positions match Hyprland after a logout/relogin.
- [ ] Mouse sensitivity, keyboard layout, repeat, and input device discovery work.
- [ ] `swaymsg -r -t get_inputs` shows flat acceleration and zero pointer gain; compare feel to Hyprland at the same hardware DPI and maccel profile.
- [ ] No unexpected title bars; 6 px inner and 9 px outer gaps.
- [ ] Power menu lock launches the **existing Quickshell awtarchy-lock** UI, not plain swaylock, and authenticates with PAM.
- [ ] Quickshell lockscreen in Sway matches Hyprland's saved per-monitor layout, background, custom images, clock and visualizer settings.
- [ ] Secure desktop backdrop/transition capture works on both displays, and private capture files are removed after unlock.
- [ ] `qs -c awtarchy-lock ipc call lock state` reports `secure` only after the compositor confirms the WlSessionLock.
- [ ] Emergency Super+Ctrl+L remains available to invoke swaylock without requiring Quickshell.
- [ ] Suspend and hibernate refuse to proceed if the secure Quickshell lock cannot be verified.
- [ ] Suspend/return does not corrupt monitors, cursor, or shell.

## 2. Window management and workspaces

- [ ] Alt+left mouse drag moves a floating window.
- [ ] Alt+right mouse drag resizes a floating window.
- [ ] Alt+Tab and Alt+Shift+Tab move focus between windows on one workspace.
- [ ] Keyboard focus, container move, and manual resize shortcuts work.
- [ ] Alt/Super+1 through +0 switch numbered workspaces 1–10.
- [ ] Workspace transfers up/down and left/right move the **whole** workspace.
- [ ] Browser opens on workspace 2.
- [ ] Discord/Vesktop opens on workspace 3.
- [ ] Steam opens on workspace 4 (both native and XWayland class paths).
- [ ] Spotify/YouTube Music use workspace 5 when their actual app ID matches.
- [ ] Telegram, remote access, Teams, creative apps, and OBS use 6–10 as configured.
- [ ] Two apps on separate workspaces on one monitor do not merge occupancy.
- [ ] Hidden occupied workspaces remain displayed by Quickshell.
- [ ] Sway's internal `__i3_scratch` is not displayed as a numbered workspace.
- [ ] Native scratchpad shortcuts show/hide and move utility windows as intended.
- [ ] Fullscreen windows are not unexpectedly resized or moved.

## 3. Quickshell bar and desktop utilities

- [ ] The Quickshell bar loads on both monitors with correct placement.
- [ ] No native Swaybar appears, including after a previous Quickshell failure.
- [ ] Only Awtarchy's Quickshell notification popups appear; Mako is not started by Sway.
- [ ] The previously hand-installed SwayFlyoutWindow.qml updates from its exact stock hash with a backup, without overwriting user edits.
- [ ] Bar workspace numbers, active marker, occupied markers, icons and tasks agree.
- [ ] Workspace buttons and mouse wheel switch to the expected workspaces.
- [ ] Alt+left dragging the **bar** previews another edge and saves the new edge; the pointer gesture stays active until mouse release without Sway layer-shell margin movement interrupting it.
- [ ] Bar orientation, auto-hide, size, transparency and per-monitor settings persist.
- [ ] Alt+P and Super+D open the application launcher as a **floating** window.
- [ ] Application launcher receives typing immediately from Alt+P / Super+D without hovering or clicking; Escape closes.
- [ ] Alt+right mouse-drag on the launcher and all seven layer-shell flyouts stays active until button release and applies the previewed size.
- [ ] Application launcher stays open, searches, launches and closes via Escape.
- [ ] Super+P opens the power menu as a layer-shell overlay and accepts letter shortcuts without clicking a tile.
- [ ] Escape dismisses the power menu without triggering an action; avoid testing shutdown by pressing S unintentionally.
- [ ] Clipboard, notifications, quick settings, network, Bluetooth and battery
  flyouts float, are positioned correctly and **do not close immediately**.
- [ ] Flyout position/size adjustments and monitor targeting work.
- [ ] Alt+Mouse2 resizes a flyout; Save records the new dimensions and reopen/relogin restores them on the same monitor.
- [ ] Reset and copy-to-other-monitor still use the original Quickshell state, not a competing Sway geometry cache.
- [ ] Switching workspaces dismisses relevant floating panels without stale state.
- [ ] Theme picker opens as an overlay and applies a theme to **awtarchy-sway**.
- [ ] Escape dismisses the focused theme picker directly without closing any underlying Quick Settings flyout.
- [ ] Changing Sway's theme does not modify `hyprland.lua` or its theme.json.
- [ ] Foot's live palette and Micro colors match expected theme behavior.
- [ ] Quickshell reload/relogin retains preferences and does not restart endlessly.
- [ ] Audio widgets, media keys, brightness, date/time, network and battery readouts.
- [ ] Focus-on-outside-click dismissal is **not implemented** on Sway yet;
  explicit toggle, Escape and workspace-change dismissal are expected.

## 4. Applications and screenshots

- [ ] Alt+Shift+B opens floating btop at ~80% × 85% screen size.
- [ ] Alt+Shift+M or Super+Shift+M toggles floating maccel at ~90% × 96%, without spawning duplicates.
- [ ] Pressing a utility shortcut again closes its floating instance on the active workspace; a floating instance on another workspace is closed and reopened locally.
- [ ] A manually tiled utility is never killed by its toggle shortcut.
- [ ] Super+W toggles floating wallpicker; Super+Ctrl+M and Super+Alt+G/O toggle their Hyprland-equivalent utilities.
- [ ] Super+T opens/closes the Sway-only theme picker; selecting a theme recolors active and inactive window borders immediately and after relogin/reload.
- [ ] Wiremix, Qalc, default-applications TUI and Foot/Yazi launch correctly.
- [ ] Super+Shift+X selects an area, copies it and opens **Satty**.
- [ ] Super+Shift+S selects a window, copies it and opens Satty.
- [ ] Super+Shift+D/F selects a display and opens Satty.
- [ ] Satty can annotate, save and cancel without leaving stale capture locks.
- [ ] Taking another screenshot while Satty is open works.
- [ ] No Hyprland-only screenshot command is executed in Sway.
- [ ] The application launcher and notifications do not create unintended
  numbered-workspace occupancy when opened.

## 5. Gaming, portals and known compromises

- [ ] Steam, Proton, gamescope and native Wayland games launch as expected.
- [ ] Fullscreen, input focus, Alt+Tab, frame pacing and display refresh remain stable.
- [ ] `swaymsg -r -t get_outputs` confirms `allow_tearing` on both active outputs.
- [ ] Fullscreen Steam/Proton and gamescope windows are eligible for immediate page flips; confirm behavior with real GPU/display measurements.
- [ ] VRR remains opt-in and must be assessed independently of tearing.
- [ ] OBS/Discord screen sharing and their xdg-desktop-portal backends work.
- [ ] Clipboard, screenshots, file dialog and desktop portals work after reboot.
- [ ] Sway's folder MIME association matches the file manager selected in Awtarchy (PCManFM-Qt by default), without overriding any unrelated MIME defaults.
- [ ] Opening a directory from another application launches the selected file manager; distinguish this from an application's own GTK/Qt file chooser.
- [ ] A user-provided `sway-mimeapps.list` folder override is preserved and produces an explicit warning instead of being overwritten.
- [ ] Power menu lock, suspend and shutdown have correct safeguards.
- [ ] Idle inhibition during fullscreen games and calls behaves as intended.
- [ ] Sway logout returns to Ly without affecting Hyprland startup.
- [ ] Hyprland still starts with its original Quickshell and monitor settings.

**Explicit differences:** Standard Sway does not provide Awtarchy's Hyprland
digital-vibrance shaders, blur/rounding/animation effects or verified Screen
Share Guard capture exclusion. Do not rely on screen-share privacy exclusions
in this session. Screenshot freeze-frame behavior from hyprpicker is also
unavailable; Satty editing remains supported.

## Collect focused diagnostics

From an actual **Sway** terminal:

```bash
swaymsg -r -t get_workspaces
swaymsg -r -t get_outputs
qs -c awtarchy-sway ipc call control ping
python3 "$HOME/.config/sway/awtarchy-trial/workspace-state.py"
```

For a misassigned application, use `swaymsg -r -t get_tree` and inspect the
window's `app_id` and `window_properties.class`; XWayland often reports
only class. Run read-only checks before editing rules.

To return to Ly from Sway, use `swaymsg exit` in a Sway terminal.
Hyprland remains installed and is not modified by the trial.
