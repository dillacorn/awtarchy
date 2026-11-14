# Sway (Awtarchy Trial): extended first-login checklist

This is an experimental standard-Sway session. It does **not** replace Hyprland.
The checklist includes features implemented in source, behaviors requiring a live
test, and known unsupported Hyprland-only capabilities.

Before testing: use `awtarchy compositor` to **Review Sway managed config
changes** and then **Apply Sway managed updates**. The review checks the
registered checkout's remote revision without changing files; Apply safely
fast-forwards a clean trial checkout after confirmation.
Preserve imported DP-1/DP-3 display modes and any customized Sway configuration.
A commit and static CI pass do not prove working Quickshell/Wayland behavior.

## 1. Session, display and input

- [ ] Ly lists both **Hyprland** and **Sway (Awtarchy Trial)**.
- [ ] Cursor is visible after login and remains visible over games and flyouts.
- [ ] DP-1 activates 1920×1080 at approximately 400.002 Hz.
- [ ] DP-3 activates 1920×1080 at approximately 239.761 Hz.
- [ ] Monitor positions match Hyprland after a logout/relogin.
- [ ] Saved Awtwall/awww wallpaper is visible on both monitors after login and after `swaymsg reload`; Sway must not overlay it with a solid-color swaybg background.
- [ ] Mouse sensitivity, keyboard layout, repeat, and input device discovery work.
- [ ] `swaymsg -r -t get_inputs` shows flat acceleration and zero pointer gain; compare feel to Hyprland at the same hardware DPI and maccel profile.
- [ ] No unexpected title bars; 6 px inner and 9 px outer gaps.
- [ ] Power menu lock launches the **existing Quickshell awtarchy-lock** UI, not plain swaylock, and authenticates with PAM.
- [ ] Quickshell lockscreen in Sway matches Hyprland's saved per-monitor layout, background, custom images, clock and visualizer settings.
- [ ] Secure desktop backdrop/transition capture works on both displays, and private capture files are removed after unlock.
- [ ] `qs -c awtarchy-lock ipc call lock state` reports `secure` only after the compositor confirms the WlSessionLock.
- [ ] No emergency swaylock shortcut is installed; the Sway lock action must refuse to succeed if the Quickshell WlSessionLock is unavailable.
- [ ] Suspend and hibernate refuse to proceed if the secure Quickshell lock cannot be verified.
- [ ] Suspend/return does not corrupt monitors, cursor, or shell.

## 2. Window management and workspaces

- [ ] Super+Alt+N/M/V toggle noalt/mouse/vm natively, including same-shortcut reset and switching directly between modes.
- [ ] Quickshell bar mouse icon toggles/resets the real mode; displayed state matches `swaymsg -r -t get_binding_state` after reload.
- [ ] noalt keeps Super desktop shortcuts/Alt+Tab; vm reserves Super+Alt host shortcuts while passing other shortcuts to applications.
- [ ] In Sway mouse mode, normal click/paste must remain intact; Alt is still required for drag/resize (documented stock-Sway limitation).
- [ ] Alt+left mouse drag moves a floating window.
- [ ] Alt+right mouse drag resizes a floating window.
- [ ] Alt+Tab and Alt+Shift+Tab cycle across tiled and floating application windows on the same workspace, including ProtonUp-Qt dialogs above Firefox/Foot; do not change other monitors' focus.
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
- [ ] Fullscreen windows are not unexpectedly resized or moved; Super+P power menu must be visible above a fullscreen game on the focused monitor (overlay layer), with normal Escape dismissal.

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
- [ ] Alt+Mouse2 resizes all seven Sway flyouts; Save becomes available after a size change even when Sway has not reported an updated window frame.
- [ ] Save writes the requested width and height to the shared `~/.cache/awtarchy/quickshell-state.json` for the active monitor, and reopening/relogin restores those exact dimensions.
- [ ] Reset/Discard do not persist a modified size, and Copy still propagates the selected requested dimensions to another monitor.
- [ ] Reset and copy-to-other-monitor still use the original Quickshell state, not a competing Sway geometry cache.
- [ ] Switching workspaces dismisses relevant floating panels without stale state.
- [ ] Theme picker opens as an overlay and applies a theme to **awtarchy-sway**.
- [ ] Escape dismisses the focused theme picker directly without closing any underlying Quick Settings flyout.
- [ ] Changing Sway's theme does not modify `hyprland.lua` or its theme.json.
- [ ] Foot's live palette and Micro colors match expected theme behavior.
- [ ] Quickshell reload/relogin retains preferences and does not restart endlessly.
- [ ] Audio widgets, media keys, brightness, date/time, network and battery readouts.
- [ ] In Quick Settings on either monitor, select the other monitor's brightness, change it (for example 35% to 75%), and verify the bar immediately updates and stays at the new value after a refresh, closing/reopening the flyout and selecting that output again.
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
- [ ] ProtonUp-Qt launches floating and centered at approximately 45% × 45% of the active output; its Add Version, About and other child dialogs float without being forced to main-window size.
- [ ] PulseAudio Volume Control, Pulsemixer, Tips TUI, hyprbars (when present), Wiremix and the existing floating utilities follow Hyprland's per-app sizes in Sway.
- [ ] XWayland variants of Awtarchy floating utilities follow the same rule through WM_CLASS, and ordinary XWayland dialogs float without tiling unrelated applications or games.
- [ ] Super+Shift+X selects an area, copies it and opens **Satty**.
- [ ] Super+Shift+S selects a window, copies it and opens Satty.
- [ ] Super+Shift+D selects a display and copies it to the clipboard **without** Satty; Super+Shift+F selects a display and opens Satty.
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
- [ ] OBS/Discord screen sharing and their xdg-desktop-portal backends work, with the Sway Quickshell selector (no Fuzzel) after restarting xdg-desktop-portal-wlr without interrupting an active recording. Check keyboard/mouse source selection, Escape cancellation, and fullscreen overlays on both monitors.
- [ ] Clipboard, screenshots, file dialog and desktop portals work after reboot.
- [ ] Sway's folder MIME association matches the file manager selected in Awtarchy (PCManFM-Qt by default), without overriding any unrelated MIME defaults.
- [ ] With PCManFM-Qt fully closed, press Super+E in Sway after applying the trial update. Verify the dark Kvantum/MateriaDark palette and Papirus-Dark icons from existing qt6ct config.
- [ ] Verify a freshly launched application's folder-opening action uses the selected file manager and correct Qt6 palette. Previous processes may retain the old environment.
- [ ] The root-owned Sway Ly wrapper is backed up/upgraded only when stock; custom edits are preserved. A normal future login inherits the Qt5/Qt6 theme list for every Sway-launched application.
- [ ] A user-provided `sway-mimeapps.list` folder override is preserved and produces an explicit warning instead of being overwritten.
- [ ] Power menu lock, suspend and shutdown have correct safeguards.
- [ ] `python3 ~/.config/sway/awtarchy-trial/idle-manager.py status` reports `running` without duplicates after Sway reload or managed update.
- [ ] Idle after 3 minutes locks using the existing secure Quickshell lockscreen (never swaylock).
- [ ] Idle after 4 minutes powers displays off; input wakes the displays to the secure lockscreen.
- [ ] Idle after 9 minutes attempts suspend without overriding systemd/logind sleep inhibitors, and returns to usable displays upon wake.
- [ ] Enable the bar's Keep Awake control: no 3/4/9 minute actions occur. Disable it and verify idle returns after new user activity.
- [ ] Active OBS recording/streaming/replay and fullscreen games protect idle actions; Teams call sleep inhibitors remain honored. Vesktop/Telegram are not granted unconditional Keep Awake.
- [ ] A failed/unavailable Quickshell secure lock prevents automatic display-off or automatic suspend.
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
