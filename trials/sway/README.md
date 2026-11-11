# SwayWM experimental Awtarchy integration

Branch: SwayWM_Migration_Trial_Investigation

**Not released or merged.** Sway is an optional second compositor;
Hyprland remains the default and its existing session/configuration is preserved.
SwayFX is deferred and must never be installed alongside Sway.

## Lesson from Jay and Mango

The actual config/hypr/hyprland.lua, its scripts, and Quickshell UI are the
acceptance specification. Native numbered workspaces, gaps, pointer, ALT+mouse,
ALT+TAB, floating Foot utilities, monitor settings and Quickshell shortcuts
must be evaluated together. Source/CI successes are not live-session proof.
Jay failed these checks; Mango tags did not match expected workspaces.

## Isolated installation

- Trial config: ~/.config/sway/awtarchy-trial/config
- Generated shell: ~/.config/quickshell/awtarchy-sway
- Ly session: Sway (Awtarchy Trial)
- System session launcher: /usr/local/bin/awtarchy-sway-session
- Portal preference: ~/.config/xdg-desktop-portal/sway-portals.conf
- Core packages: sway, swaybg, swayidle, swaylock, xdg-desktop-portal-wlr
- Hyprland config, Quickshell profile and Hyprland Ly session remain installed.

The updater compares the installed Sway config to its recorded baseline. If
it is still unmodified, the updater can install new window rules while keeping
the exact imported monitor block. User-modified configs and other edited files
are preserved, with a backup before any managed replacement. Removals use exact Awtarchy package ownership and non-cascading
pacman transactions. Shared packages are preserved.

## Compatibility matrix

Implemented means committed source, **not live verified**.

| Hyprland feature | Sway trial |
| --- | --- |
| 6px inner/9px outer gaps | Native config |
| ALT+mouse drag and resize | Native Sway modifier |
| ALT+TAB / ALT+SHIFT+TAB | Focus next/previous; stacking semantics differ |
| Workspaces 1-10 | Native; not tags |
| Move whole workspace to monitor | Directional Sway command |
| Floating btop at 80% x 85% | Native Foot app ID rule |
| Persistent monitor modes | Guarded one-time Hyprland import |
| Cursor image/theme/size | Native Sway seat settings |
| Quickshell workspace/monitor | Sway IPC tree counts hidden occupied workspaces; live test required |
| Quickshell menus/power/notifications | Explicit floating title rules, native positioning and safe manual close; live test required |
| Sway session lock | swaylock fallback; Quickshell-specific extras limited |
| Clipboard screenshots | grim/slurp/wl-copy |
| App workspace assignments | Ported initial rules; XWayland still needs verification |
| Hyprland Screen Share Guard | **Unavailable; private panels fail closed** |
| Digital vibrance via shaders | **No confirmed native equivalent** |
| Hyprland blur/animations/rounding | **Not provided by standard Sway** |
| Hyprland special-workspace geometry | Native Sway scratchpad differs |
| noalt/mouse/vm submaps | Not yet fully ported |
| Per-window Quickshell flyout placement | Sway IPC positioning implemented; live test required |
| Hyprland-specific utilities | Must be handled individually, not dispatched blindly |

Do not advertise unimplemented capture protection, shader effects, or input
modes. Where a feature is unsupported, return an explicit error or hide the
unsafe UI instead of acknowledging a no-op.

## Validation requirements

The experimental GitHub Actions workflow runs test-sway-trial.py, Bash and
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
6. Verify fullscreen gaming, frame pacing, VRR and portals independently.
   Screen Share Guard remains explicitly unavailable.

Use swaymsg exit in a Sway terminal to return to Ly, then select Hyprland.
Do not remove Hyprland, merge the trial, or release it based only on CI.

Extended checklist: [TEST_CHECKLIST.md](TEST_CHECKLIST.md). Satty screenshot annotation,
Alt+bar edge dragging, maccel and theme isolation are staged in this branch,
but must be confirmed in a real Sway session. SwayFX is not part of this test.
