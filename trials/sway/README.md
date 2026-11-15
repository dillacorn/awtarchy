# Maintained optional Sway compositor in Awtarchy v4.2.0

Sway is an optional second compositor. Hyprland remains the default.
Both can be installed at once with independently managed compositor and
Quickshell profiles. Use `awtarchy compositor` to manage them.
Older trial-specific paths remain for safe upgrades.
SwayFX is deferred and must never be installed alongside Sway.

## Lesson from Jay and Mango

The actual config/hypr/hyprland.lua, its scripts, and Quickshell UI are the
acceptance specification. Native numbered workspaces, gaps, pointer, ALT+mouse,
ALT+TAB, floating Foot utilities, monitor settings and Quickshell shortcuts
must be evaluated together. Source/CI successes are not live-session proof.
Jay failed these checks; Mango tags did not match expected workspaces.

## Isolated installation

- Sway config (retained legacy path): ~/.config/sway/awtarchy-trial/config
- Generated shell: ~/.config/quickshell/awtarchy-sway
- Ly session: Sway (Awtarchy); older trial entries remain until upgraded
- System session launcher (used internally by Ly and TTY): /usr/local/bin/awtarchy-sway-session
- TTY command: `sway` (managed `~/.local/bin/sway`, no arguments). `sway -C` or any other arguments invoke native `/usr/bin/sway`.
- Ly is optional. Existing personal `sway` launchers are preserved.
- Portal preference: ~/.config/xdg-desktop-portal/sway-portals.conf
- Screencast selector: ~/.config/xdg-desktop-portal-wlr/sway (Sway-only Quickshell overlay with exact portal-source protocol; Fuzzel not used by OBS)
- Core packages: sway, swaybg, swayidle, xdg-desktop-portal-wlr (no swaylock or Mako installed for this Quickshell-based session)
- Hyprland config, Quickshell profile and Hyprland Ly session remain installed.

The updater compares the installed Sway config to its recorded baseline. If
it is still unmodified, the updater can install new window rules while keeping
the exact imported monitor block. User-modified configs and other edited files
are preserved, with a backup before any managed replacement. Removals use exact Awtarchy package ownership and non-cascading
pacman transactions. Shared packages are preserved.

## Compatibility matrix

Automated checks cover source and configuration; hardware-specific behavior still needs live testing.

| Hyprland feature | Awtarchy Sway |
| --- | --- |
| 6px inner/9px outer gaps | Native config |
| ALT+mouse drag and resize | Native Sway modifier |
| ALT+TAB / ALT+SHIFT+TAB | Native Sway focus when only tiled applications exist; Sway-only focused-workspace leaf cycling bridges floating and tiled application windows |
| Workspaces 1-10 | Native; not tags |
| Move whole workspace to monitor | Directional Sway command |
| Floating btop at 80% x 85% | Native Foot app ID rule |
| Floating utility toggles | Sway tree-based exact app-ID toggle; close local floating instance, relocate remote floating instance, never close tiled windows |
| Floating utility compatibility | Shared tools match Wayland app IDs and XWayland classes; Sway uses `nwg-displays` instead of the Hyprland-only `hyprmoncfg`. ProtonUp-Qt floats at 45% × 45%, with independent dialogs. |
| Theme picker and window borders | Super+T toggles Sway Quickshell picker; selected active/inactive theme border colors apply through Sway IPC and on compositor reload |
| Persistent monitor modes | Guarded one-time Hyprland import; Super+Ctrl+M opens native `nwg-displays`, whose private Sway `outputs` and `workspaces` includes persist adjustments without changing Hyprland |
| Saved wallpaper through Sway reload | Awtwall/awww retains background ownership; no competing `output * bg` swaybg layer and `swaybg_command -` prevents new compositor-managed backgrounds |
| Quick Settings brightness per output | The Sway renderer sends the selected DP-1/DP-3 brightness target separately from the flyout's own output, preserving the readback after selection and updates |
| Cursor image/theme/size | Native Sway seat settings |
| Mouse acceleration | Explicit `accel_profile flat`, `pointer_accel 0`, matching Hyprland; maccel remains independent |
| Fullscreen game tearing | `output * allow_tearing yes`, `max_render_time off`, app-level allow for Steam/Proton/gamescope and matched game classes; hardware/runtime verification required |
| Quickshell workspace/monitor | Sway IPC tree counts hidden occupied workspaces; live test required |
| Quickshell menus/power/notifications | Seven flyouts generated as layer-shell panels with output-local margins; power menu plus secondary shades use overlay layer to cover fullscreen windows; live testing required |
| Sway session lock | Uses the same installed `awtarchy-lock` QML, PAM authentication, per-monitor profiles, custom media and shared theme as Hyprland; private Sway capture/manager restore frozen-backdrop transitions. No swaylock shortcut or fallback; unavailable/failed WlSessionLock returns failure. |
| Directory default application | Sway reconciles `inode/directory` with Awtarchy's file-manager choice and preserves custom overrides. The Sway Ly launcher now advertises qt5ct:qt6ct; Qt6 PCManFM-Qt can use its existing qt6ct/Kvantum/MateriaDark configuration. The updater refreshes the live Sway Quickshell/D-Bus environment and backs up/replaces only known unmodified root-owned Ly wrappers. The Sway compositor inherits the new environment on its next normal login. |
| Automatic Sway idle/suspend | Native swayidle daemon, started once per actual Sway socket and refreshed on managed updates/reloads. 3-minute secure Quickshell lock, 4-minute display power-off, 9-minute suspend (no bypass of logind sleep inhibitors). Keep Awake and active OBS output block these actions. Sway-native idle inhibitors protect fullscreen games and media; personal-app inhibition differences from Hyprland still need live testing. |
| OBS screencast source picker | Quickshell theme-aware fullscreen overlay with keyboard/mouse selection and Escape cancellation. The chooser returns only exact monitor/window entries provided by xdg-desktop-portal-wlr. Awtarchy updates automatically refresh the Sway backend only when PipeWire proves no xdpw stream is active; otherwise it preserves the stream and defers the refresh. Never auto-approve screen sharing. |
| Clipboard screenshots | Super+Shift+D directly captures the actively focused output via Sway IPC + grim, saves a unique PNG in ~/Pictures/Screenshots and copies it to the clipboard, without a picker or Satty. Super+Shift+F retains manual display selection and Satty editing. Rapid direct captures queue up to five seconds instead of being silently discarded. Every successful grim capture (direct, Satty-backed, or Print) triggers the selected 180ms "Classic: tighter double-click" (15% PipeWire volume), before optional Satty editing or saving. No flash or notification enters the following screenshot; audio failure never affects captures. In Quick Settings → Awtarchy → Sound (expanded by default), enable or mute the iconic Awtarchy login sound separately from screenshot sounds. The screenshot master On/Off switch and the Screenshot sounds Options control provides independent direct/Satty/Print controls. Preferences are stored once at $XDG_STATE_HOME/awtarchy/screenshot-sound.conf (default ~/.local/state/awtarchy/screenshot-sound.conf) and apply to both Sway and Hyprland sessions. Sway installs the exact config/hypr/sounds/awtarchy-login.mp3 privately and plays it once after Quickshell is ready at session login (never on swaymsg reload). Login playback retries briefly while USB audio is initializing; muting login never disables screenshots. No new package or sound file is required. |
| Awtarchy preferences card | Compact inline Sound row with independently controllable Login and Screenshots On/Off buttons; Options reveals per-shortcut sound controls only when requested. Cursor and Lockscreen have short Show/Hide rows with no extra descriptions. Existing theme, animation, appearance, weather and Edit Layout controls remain available on expansion. Preferences and customization persist unchanged. |
| App workspace assignments | Ported initial rules; XWayland still needs verification |
| Hyprland Screen Share Guard | **Unavailable; private panels fail closed** |
| Digital vibrance via shaders | **No confirmed native equivalent** |
| Hyprland blur/animations/rounding | **Not provided by standard Sway** |
| Hyprland special-workspace geometry | Native Sway scratchpad differs |
| noalt/mouse/vm submaps | Native Sway mode toggles via Super+Alt+N/M/V. `noalt` retains Super desktop shortcuts; `vm` reserves Super+Alt host controls. The bar mouse icon toggles/reset the compositor mode. Stock Sway cannot perform Hyprland-style unmodified mouse drag/resize through mode blocks: Alt+mouse remains required in `mouse` mode. |
| Per-window Quickshell flyout placement | QML layer-shell anchors update without post-map Sway move/resize commands; live test required |
| Hyprland-specific utilities | Must be handled individually, not dispatched blindly |

Do not advertise unimplemented capture protection, shader effects, or input
modes. Where a feature is unsupported, return an explicit error or hide the
unsafe UI instead of acknowledging a no-op.

## Sway display settings and Hyprmoncfg migration

`Super+Ctrl+M` starts the Sway-compatible `nwg-displays`, not
`hyprmoncfg`. Awtarchy installs it from the official Arch repositories.
Its saved monitor rules go to `~/.config/sway/awtarchy-trial/outputs` and
Sway reads them after the initial imported Hyprland monitor block. Its
workspace assignments use `~/.config/sway/workspaces` as generated by
nwg-displays. These are user-adjustable Sway files, and managed updates
preserve any modified values without rewriting Hyprland monitor settings.

On first installation launched from a live Hyprland session, Awtarchy
imports the active layout (resolution, refresh rate, scale, position,
supported transforms and VRR). When hyprmoncfg reports an active saved
profile with the same enabled monitor set, the importer can also carry
over disabled outputs and explicit manual workspace-to-output rules.
It refuses nonmatching profiles or custom existing Sway output/workspace
rules; no saved Hyprmoncfg JSON files are edited. Other named saved
profiles are not automatically duplicated or synchronized, and
Hyprland-only HDR/color/mirroring and automatic profile-switching features
must not be represented as supported Sway equivalents.

The first trial update after this change may be launched from a checkout
that still contains the old compositor manager. In that case, refresh the
registered checkout before starting the updated manager so it installs
nwg-displays before the new Sway binding is applied.

## Sway PCManFM-Qt theme

PCManFM-Qt 2.x uses Qt6. The earlier Sway Ly wrapper exported only
`QT_QPA_PLATFORMTHEME=qt5ct`, so the qt6ct palette/style/icon settings
could be bypassed. Use the Arch-supported `qt5ct:qt6ct` list instead;
the user's qt5ct/qt6ct, Kvantum and PCManFM-Qt settings are unchanged.

When managed files update, Sway's session.sh imports this theme into
D-Bus/systemd and the Quickshell manager is restarted with it. Both
Sway's Super+E file-manager bindings pass the correct Qt platform-theme list
even before the next session login. The compositor itself inherits the new
environment only from the root-owned Ly launcher on next login. The
privileged wrapper is upgraded only if it has a recognized, unmodified
original stock hash, with a root-owned backup. Any custom launcher is kept.

An existing PCManFM-Qt process retains its original environment; close it
normally before testing a newly opened window. Check `pacman -Q qt6ct
kvantum` if the dark theme still does not appear. No package changes or
existing applications are forced to restart.

## Managed Sway update source

The compositor menu reads a registered local Git checkout. A stale checkout
previously produced a misleading `update=0` even when GitHub had newer Sway
changes. The read-only review now checks the remote branch head before
claiming to be current. The confirmed Apply action fast-forwards only a
clean checkout of the named Sway trial branch, then applies managed file
changes and activates Sway in place. Known original installed compositor
manager versions are upgraded with a backup as a managed file, so subsequent
menu operations gain the source freshness check; custom manager edits remain
untouched. Dirty or diverged checkouts fail safely
without discarding edits or rewriting history.

The screen-picker portal backend reads its configuration on service start.
The updater refreshes it automatically only after a chooser-config update
and only if no `xdpw-stream-*` PipeWire node is present. Unknown PipeWire
state or an active screencast defers the restart rather than interrupting a
user's screen sharing. No logout is needed.

## Sway idle policy (experimental)

Awtarchy now starts swayidle with the Sway-specific managed policy at
`~/.config/sway/awtarchy-trial/swayidle.conf`; no swaylock is used.
The manager checks the exact active Sway session and PID identity so config
reloads do not spawn duplicate daemons or affect Hyprland. New managed idle
files activate during the Sway updater without logging out.

The idle timers use 180 seconds to lock (secure awtarchy-lock), 240 seconds to
switch displays off, and 540 seconds to request suspend. Before and after
system sleep the same lock and display handlers run. If the lock cannot be
verified secure, automatic display-off and suspend refuse to proceed. The
suspend action honors logind sleep inhibitors, unlike the manual power menu's
force-allowed suspend. The existing Awtarchy Keep Awake indicator and active
OBS recording/streaming/replay protect idle actions; Teams sleep inhibitors
are preserved. Sway's native visible-window idle inhibition remains active,
including fullscreen games. This is not identical to Hyprland's custom
60-second bar hide, 120-second dim, or 4-hour protected-session safeguard.

For read-only diagnostics in the Sway session:

```bash
python3 "$HOME/.config/sway/awtarchy-trial/idle-manager.py" status
bash "$HOME/.config/sway/awtarchy-trial/idle-action.sh" check
systemd-inhibit --list --no-pager
```

## Sway Quickshell window model (experimental)

The seven editable Awtarchy flyouts are regular application
`FloatingWindow` toplevels in the Hyprland source. Sway's title-based
floating rules can be applied after the first tiled frame, causing the
visible tile -> float -> move transition reported during testing.

The Sway-only renderer now replaces exactly those seven windows with
`SwayFlyoutWindow.qml`, a native `PanelWindow` using wlroots layer-shell.
It uses the selected monitor, edge placement, current panel dimensions,
and bar size to set **anchors and margins before mapping**. It does not
reserve screen space or run `swaymsg get_tree`/move/resize commands for
these surfaces. Notification toast popups, power menu and theme picker
already use layer-shell and remain unchanged. The original Hyprland QML
sources are not edited.

This removes the **regular tiled-window code path** by construction.
Sway flyouts now use Alt+right-drag with a dimension preview, committing the
layer-shell resize on release to avoid breaking the pressed-pointer grab.
The resize callback goes through the original launcher/menu size override.
Sway's generated owners now treat the requested layer-shell dimensions as
the authoritative live values for Save, Copy, Restore and the unsaved-change
indicator. The original floating-window owners on Hyprland still measure the
compositor-reported window size. These paths share the existing persistent
per-monitor settings backend, without introducing separate Sway geometry
state. Live reopen/relogin verification is still required.
This is not yet a live animated surface resize, which would need a verified
way to retain the pointer grab while changing layer-shell geometry.
The shortcut-opened launcher and power menu request immediate keyboard focus.
Sway's Alt+left bar drag keeps layer-shell margins unchanged until pointer
release; changing the bar geometry during an active grab had cut the gesture short.
Sway no longer launches a native swaybar or Mako fallback that competes with
the Awtarchy bar and notifications.
It does not prove the actual first rendered frame, keyboard focus or
menu dismissal behavior until a live Sway/Quickshell session is tested.
The managed updater preserves personal modifications and previously
imported DP-1/DP-3 display profiles. New generated Sway QML components are
installed automatically; exact copies manually staged during the earlier
missing-component recovery are recognized and upgraded with a backup.
Unknown or customized files remain protected.

The Sway-only `lock-manager.sh` and `lock-capture.sh` use the existing
`awtarchy-lock` Quickshell profile and its shared
`~/.cache/awtarchy/quickshell-state.json` per-display settings. Only output
capture discovery is compositor-specific (`swaymsg` instead of `hyprctl`).
No lockscreen settings are copied or reset, and the Hyprland locker stays
unchanged. Capture transition and secure lock confirmation still need a live
test before treating this as complete security validation.

Sway session startup also runs `mime-parity.py apply` for `inode/directory`.
The script reads the existing user choice from
`~/.config/awtarchy/default-applications.json`, backs up a changed
`~/.config/mimeapps.list`, changes just the folder association, and refuses
an explicit Sway-only override or unsafe existing file. This shared XDG MIME
entry affects both desktops, as requested; no unrelated MIME types or
per-application file chooser portal settings are changed.

## Validation requirements

The experimental GitHub Actions workflow runs Sway flyout-layer, shell and IPC tests, Bash and
Python syntax checks, isolated QML generation and the real Sway config parser.
Static tests alone do not establish display, input, focus, animation or gaming
functionality. Each needs runtime verification.

Before any live login, check the branch/commit, confirm the tests have passed,
review the compositor manager's installation plan, and preserve Hyprland.

### Initial live-session checks

1. Confirm original Hyprland monitor positions, refresh rates and desktop first.
2. Add Sway alongside Hyprland through the compositor manager. Review the
   package operations and imported Sway output block before reboot.
3. Select Sway (Awtarchy Trial) in Ly after reboot.
4. Confirm visible cursor; 400/240Hz modes; 6/9px gaps; window decorations;
   ALT+mouse; ALT+TAB; btop float/size; numbered workspaces; moving an entire
   workspace up and back down.
5. Confirm native Quickshell workspace bar and control IPC. From a Sway terminal,
   run: qs -c awtarchy-sway ipc call control ping
   Expected: ok. Check ALT+P, SUPER+D, SUPER+P, clipboard, notifications.
6. Verify fullscreen gaming, immediate page flips/tearing, frame pacing, VRR and portals independently. Tearing permissions do not prove that the driver actually presented a torn frame.
   Screen Share Guard remains explicitly unavailable.

Use `swaymsg exit` in a Sway terminal to return to Ly or your original TTY. If using a TTY, start Hyprland with `hypr`; if using Ly, select Hyprland from the session list.
Do not remove Hyprland, merge the trial, or release it based only on CI.

Extended checklist: [TEST_CHECKLIST.md](TEST_CHECKLIST.md). Satty screenshot annotation,
Alt+bar edge dragging, floating utility toggles, maccel and theme isolation are staged in this branch,
but must be confirmed in a real Sway session. SwayFX is not part of this test.
