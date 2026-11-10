# Jay first-login acceptance checklist

Status: **not approved for the full-feature test flight**. Use this after the
remaining parity blockers are closed. This checklist records the regressions
seen during the first MangoWM trial and other Awtarchy-specific integrations.

## First live trial, 2026-11-10

Observed (not yet corrected in a live Jay session):

- Jay 1.15.0 launched from Ly as **Jay (Awtarchy Trial)**.
- User reported both display resolution/refresh rates appeared normal;
  exact observed values and subsequent-login persistence remain unchecked.
- Mouse cursor was invisible. The branch now proposes a software-cursor
  fallback; verify visually before marking this fixed.
- Window title bars were visible: the original TOML incorrectly nested
  `show-titles = false` under `[theme]`. A top-level fix is staged but
  still needs a second-login test.
- Hyprland-like inner/outer gaps were missing. Jay 1.15 TOML has no
  corresponding keys; this is a feature limitation, not a missed setting.
- ALT+CTRL+SHIFT+Up moved a workspace upward, but Down did not restore it.
  Check focus/workspace state and Jay's directional-output behavior.
- Quickshell keyboard-driven surfaces, including SUPER+P power menu, did
  not open. Inspect the persistent `~/.cache/awtarchy/quickshell-jay.log`
  from Hyprland before changing startup or QML IPC code.
- User successfully left Jay and returned to the existing Hyprland session.

Do not mistake static CI or branch configuration corrections for verified
runtime fixes. The installed Jay TOML preserves imported monitor settings;
run the guarded appearance migration from `README.md` in this directory
before retesting.

## Before changing login sessions (while in Hyprland)

- [ ] Hyprland remains available in Ly; no forced package removal or config replacement
- [ ] Inspect `git status --short` in the Jay trial checkout and confirm the intended branch
- [ ] Run `bash trials/jay/setup.sh --check` (must not alter user or system files)
- [ ] Verify `hyprctl -j monitors` reports the **real** resolutions, connector names and refresh rates
- [ ] Only a **fresh** Jay config imports that active layout; subsequent Jay edits are independent
- [ ] Check `~/.config/jay/config.toml`: readable sections and a saved `[[outputs]]` record for every active display

## First Ly login / graphics

- [ ] Select **Jay (Awtarchy Trial)**; a failed Jay login leaves Hyprland selectable
- [ ] Run `bash "$HOME/.config/jay/awtarchy-trial/diagnose.sh"` (read-only)
- [ ] DP-1 BenQ Zowie uses the *actual* preferred high refresh rate (400 Hz if enabled in Hyprland)
- [ ] DP-3 ViewSonic uses the correct refresh rate; **no 60 Hz fallback or severe artifacting**
- [ ] Screens are in the correct order, orientation, scale, and position with no manual per-login adjustment
- [ ] Log out and re-enter Jay to verify the above persists; then return to Hyprland and verify no changes
- [ ] Appropriate render GPU selected; no blank frame, unexpected software renderer, or compositor startup errors

## Native workspaces and input modes

- [ ] ALT+1..0 and SUPER+1..0 switch globally numbered workspaces, **not same-number per-output tags**
- [ ] Existing windows on a different display are focused/visited rather than creating another number-1 tag
- [ ] ALT/SUPER+SHIFT+1..0 moves the selected window
- [ ] SUPER+CTRL+SHIFT+arrows moves **the whole workspace** to the neighboring output; verify both directions
- [ ] Quickshell workspace arrows also move workspaces in all directions
- [ ] SUPER+ALT+N toggles noalt mode; **the current mode appears on the bar**
- [ ] ALT shortcuts pass through to a focused game in noalt, and normal shortcuts recover with SUPER+ALT+N
- [ ] SUPER+ALT+M mouse mode and SUPER+ALT+V VM mode enter/leave cleanly, including transitions between modes
- [ ] Mouse drag, resize, floating/fullscreen, focus across monitors and keyboard repeat feel correct

## Awtarchy shell and applications

- [ ] Quickshell bar starts on every monitor; tray, clock, task icons, active title and workspaces are correct
- [ ] ALT+P / SUPER+D launcher opens, searches and launches an app, closes, and opens on the other monitor
- [ ] **ALT+SHIFT+ENTER** starts the configured Foot terminal
- [ ] **SUPER+ALT+A** opens Default Applications as a **floating 540x460 Foot window**, not tiled
- [ ] Other floating utilities (Qalc, Wiremix, btop, Yazi, wallpaper picker) open with expected class/size
- [ ] Clipboard history, notifications, network, Bluetooth, battery, volume and Quick Settings can be opened/closed
- [ ] Flyouts close on focus loss, move to the selected display, and remain visible within screen edges
- [ ] Default applications, wallpaper, visual theme and Foot alpha 0.85 agree with the Hyprland session
- [ ] Native Quickshell bar drag and resizing do not leave a misplaced or unwanted drop overlay

## Security, power, gaming and sharing

- [ ] PolicyKit credential prompt is **actually visible and usable** (fallback is LXQt, not the Hyprland-only TUI)
- [ ] Quickshell lockscreen securely locks and unlocks; fallback Swaylock locks before suspend
- [ ] Protected idle, always-awake, inhibitors and resume-from-suspend act as intended
- [ ] Screenshot shortcuts work and never silently fail; actual screen sharing works through Jay's portal
- [ ] Screen Share Guard has equivalent tested capture exclusion; if not, **strict parity fails**
- [ ] Digital vibrance and night-light have appropriate tested equivalents; if not, **strict parity fails**
- [ ] Verify fullscreen game tearing and VRR (do not infer success from config text or supported protocol)
- [ ] Verify direct scanout, fullscreen/floating switching, frame pacing, cursor focus and Proton/XWayland
- [ ] Sunshine/Moonlight streaming works; remote capture, input and audio do not require Hyprland IPC
- [ ] Return to Hyprland from Ly; confirm existing keybinds, Quickshell and managed configs are unchanged

## Evidence to retain if anything fails

Use the read-only `diagnose.sh` report, `jay --json randr`, `jay --json tree query`,
`jay log`, and the actual Quickshell log under `~/.local/state/awtarchy/`.
For a failed monitor mode, record the connector name and *observed* Hz, not
just the intended refresh. No experimental package deletion or global config
reset is required to report a failure.
