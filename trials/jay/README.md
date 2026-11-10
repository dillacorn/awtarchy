# JayWM migration investigation

Branch: JayWM_Migration_Trial_Investigation. **Main is untouched.**
This is unreleased dual-compositor development, not a verified production desktop.
Hyprland remains the working rollback session; no automatic removals.

## Current branch implementation

- Installer runtime offers **Hyprland**, **Jay**, or **both**. Jay is selected
  through the current `aur-scan` package installation backend; Arch packages
  remain handled by pacman. Jay-only mode preserves any existing Hyprland Lua,
  idle, and privacy configuration.
- Jay has its own compositor TOML, Wayland session for Ly, portal preferences,
  native global workspaces, cross-monitor workspace movements, fullscreen
  `tearing.mode = "variant2"`, and fullscreen VRR `vrr.mode = "variant1"`.
- Jay Quickshell is generated into an **isolated profile** from Awtarchy's
  existing components. Compatible bar, launcher, wallpaper, and saved appearance
  settings share the usual Awtarchy UI state. Jay-specific IPC/permissions and
  service paths are independent of Hyprland.
- The interface uses generic Wayland workspace and foreign-toplevel APIs.
  Existing Quickshell launcher/clipboard/notification/power IPC endpoints are
  wired. A separate manager, keyboard LED reader, and native Jay input modes
  for noalt/mouse/VM are staged. Floating surfaces have initial Jay window rules.
- Jay session starts the LXQt PolicyKit agent as a temporary replacement.
  The original trusted terminal agent is still specific to Hyprland.
- Original Foot palette and `[colors-dark] alpha=0.85` remain unchanged.
- Jay Quick Settings returns its own live display/bar status and supports
  validated bar enable/auto-hide/position actions. Display-effects, submap
  picker, and Num Lock tweak panels are hidden until real compositor APIs are
  available. Unsupported actions fail explicitly instead of changing Hyprland.
- The staged preflight now has an executable CI fixture: `--check` is verified
  not to write Jay config, generated Quickshell, or Ly destination files. The
  installer preserves its action mode separately from file permission modes.
- The Jay Power Menu can use the secure Swaylock `-f` fallback without a
  subsequent Quickshell-only readiness probe incorrectly rejecting it.

## Isolated trial preparation from Hyprland

Do not use `awtarchy update` as a replacement for explicit trial staging.

```bash
git clone --branch JayWM_Migration_Trial_Investigation --single-branch https://github.com/dillacorn/awtarchy.git "$HOME/awtarchy-jay-trial"
cd "$HOME/awtarchy-jay-trial"
bash tests/test-jay-trial.sh
python3 tests/test-jay-monitor-profile.py
python3 tests/test-jay-monitor-import.py
python3 tests/test-jay-quickshell-port.py
python3 tests/test-jay-manager-port.py
python3 tests/test-jay-installer-choice.py
bash trials/jay/setup.sh --packages
bash trials/jay/setup.sh --check
bash trials/jay/setup.sh --install
```

`--packages` uses `aur-scan install jay --noconfirm`, not yay/paru for Jay.
`--check` validates available dependencies and destination conflicts without
changing installed files. `--install` stages this branch's Jay config, rendered
Quickshell, session entry, and portal preference. It fails rather than
overwriting a different existing Jay profile.

These commands are for an **early isolated investigation**; do not interpret
successful staging as proof the full experience is ready.

### One-time monitor import

The repository Hyprland Lua has generic monitor defaults, so it cannot
supply your actual active connector names/modes/refresh rates. Instead run
the read-only importer while still logged into **Hyprland**:

```bash
python3 "$HOME/awtarchy-jay-trial/trials/jay/import-hypr-monitors.py" --preview
python3 "$HOME/awtarchy-jay-trial/trials/jay/import-hypr-monitors.py" --apply
```

The importer normalizes negative monitor coordinates, makes an atomic Jay
profile with a backup, and **refuses to overwrite Jay output overrides**.
It does not change Hyprland. Manually edit the resulting separate Jay profile
or use the existing `monitor-profile.py --set` for later Jay changes.

### Login / rollback

Reboot; in Ly select **Jay (Awtarchy Trial)**. If the session fails,
select **Hyprland** in Ly at the next login. Neither session or packages are
automatically removed, and no stable Awtarchy configuration is reverted or
replaced by this isolated trial.

Inside Jay, run:

```bash
bash "$HOME/awtarchy-jay-trial/trials/jay/diagnose.sh"
jay randr show --modes
jay --json randr
```

Important shortcuts: ALT or SUPER + 1..0 selects numbered workspaces 1..10.
Add SHIFT to move the active window. ALT/SUPER+CTRL+SHIFT+arrows moves whole
workspaces between monitors. ALT+P or SUPER+D attempts the Quickshell launcher;
SUPER+P opens power; SUPER+N notifications; SUPER+C clipboard; ALT+C opens
Jay's control center; SUPER+X toggles the native `magic` overlay.
SUPER+ALT+N/M/V selects the noalt/mouse/VM input mode; press the same toggle
again to return to normal. ALT+SHIFT+R reloads Jay's configuration.
SUPER+CTRL+ALT+SHIFT+B toggles the native Jay fallback bar.

## Independent validation already performed

CI validates the installer compositor-choice logic, isolated Quickshell
rendering, monitor profile import, and real read-only `setup.sh --check`
against temporary destinations. Jay Quick Settings runs with fake compositor
output and verifies unsupported commands cannot mutate settings. Awtarchy's
existing update-session-recovery and cursor CI jobs are also run on the branch.

**Still untested:** an actual Jay compositor startup, QML load under
Quickshell 0.3.2, native display modes, graphical authentication, screen
sharing, input modes and Quickshell flyout focus, games, direct scanout, VRR,
tearing and per-monitor restore. Static CI is not a runtime pass.

## Strict parity blockers (not ready for full migration test flight)

1. **Live floating positioning:** Jay initial floating window rules exist, but
   the exact Hyprland bar-relative positioning and dynamic resize/handoff
   backend is not ported. Existing Jay placeholder explicitly fails.
2. **Quickshell Quick Settings:** Monitor/bar status and bar controls
   have a Jay-native adapter with isolated tests. Brightness, Night Light,
   vibrance, sched-ext, and direct submap controls do not yet have verified
   equivalents. Unavailable display-effects/submap/Num Lock UI is hidden.
3. **Privacy:** Dynamic Screen Share Guard controls have no verified Jay
   equivalent. Jay shows a read-only warning instead of unsafe fake toggles.
   Screen sharing and capture still need actual runtime tests.
4. **GPU color:** Hyprland digital vibrance shaders and night-light controls
   have not been ported. Native Jay color-management is not equivalent proof.
5. **Native authentication/lock:** LXQt authentication is the fallback; the
   custom Awtarchy PolicyKit TUI and Quickshell session-lock integration need
   real Jay compositor tests. Secure Swaylock fallback exists.
6. **Other parity:** exact floating app toggles, protected idle/suspend,
   full workspace/submap behavior and persistence, animations, screen zoom,
   Sunshine/Moonlight, per-monitor bar positioning and drag handling.
7. **Installer/update:** The interactive fresh-install compositor choice is
   implemented on this branch, but current stable/git update, full managed
   migration, package reconciliation and Jay-only round-trip tests are not yet
   proved. Do not assume a Jay trial checkout is installed by the main branch.

The native tearing setting, direct scanout, VRR and game performance are not
confirmed on your AMD graphics hardware. Verify with comparable games,
identical monitor refresh, game settings, frame caps and compositor state.

**Do not merge, release or treat this branch as test-flight ready until the
blockers above are resolved and the real-session tests are performed.**
