#!/usr/bin/env python3
"""Read-only Sway trial preflight; no live compositor required."""
from pathlib import Path
import ast
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
CONFIG = (TRIAL / "config").read_text(encoding="utf-8")
RUNTIME = (ROOT / "local/share/awtarchy/awtarchy-runtime.sh").read_text(encoding="utf-8")
MANAGER = (ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh").read_text(encoding="utf-8")
LAUNCHER = (ROOT / "local/bin/awtarchy").read_text(encoding="utf-8")
INSTALLER = (ROOT / "awtarchy-install.sh").read_text(encoding="utf-8")

def command(*args):
    completed = subprocess.run(args, capture_output=True, text=True, timeout=40)
    assert completed.returncode == 0, (
        f"{args!r} failed: {completed.stdout}\n{completed.stderr}")

for path in sorted(TRIAL.glob("*.py")):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
for path in sorted(TRIAL.glob("*.sh")) + [
    ROOT / "awtarchy-install.sh", ROOT / "local/bin/awtarchy",
    ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh",
    ROOT / "local/share/awtarchy/awtarchy-runtime.sh",
]:
    command("bash", "-n", str(path))

assert "SwayWM_Migration_Trial_Investigation" in INSTALLER
for phrase in ("Install Sway (preserve Hyprland)",
               "Remove Sway and eligible owned extras", "compositor_menu()"):
    assert phrase in LAUNCHER, phrase
for phrase in ('COMPOSITOR_SELECTION="hyprland"', 'compositor_has_hyprland()',
               'compositor_has_sway()', 'install_sway_repo_dependencies_stage()',
               'install_sway_session_stage()', 'copy_awtarchy_configs_stage'):
    assert phrase in RUNTIME, phrase
assert "packages_to_install+=(sway)" not in RUNTIME
assert "for package in sway swaybg swayidle nwg-displays xdg-desktop-portal-wlr" in RUNTIME
assert "sway via aur-scan" not in RUNTIME
assert "JayWM_Migration_Trial_Investigation" not in RUNTIME

bindings = {}
for line in CONFIG.splitlines():
    if line.startswith("bindsym "):
        parts = line.split(maxsplit=3)
        # Sway accepts binding flags before the keysym. Preserve checks
        # for native mode toggles even when --inhibited is required.
        if parts[1].startswith("--"):
            _, _, key, action = parts
        else:
            _, key, action = line.split(maxsplit=2)
        bindings.setdefault(key, []).append(action)
for key, expected in {
    "Mod1+Tab": "focus-cycle.py next",
    "Mod4+Mod1+n": "mode-control.sh toggle noalt",
    "Mod4+Mod1+m": "mode-control.sh toggle mouse",
    "Mod4+Mod1+v": "mode-control.sh toggle vm",
    "Mod1+Shift+Tab": "focus-cycle.py prev",
    "Mod4+Shift+d": "capture.sh display-copy",
    "Mod4+Shift+f": "capture.sh display",
    "Mod1+p": "ipc.sh launcher toggle",
    "Mod4+d": "ipc.sh launcher toggle",
    "Mod4+p": "ipc.sh powermenu begin",
    "Mod1+Shift+b": "toggle-utility.py btop",
    "Mod4+Shift+b": "toggle-utility.py btop",
    "Mod4+t": "ipc.sh themes toggle",
    "Mod4+w": "toggle-utility.py wallpicker",
    "Mod4+Control+m": "toggle-utility.py displays",
    "Mod1+Control+Shift+Down": "move workspace to output down",
    "Mod1+Control+Shift+Up": "move workspace to output up",
}.items():
    assert key in bindings, f"Missing {key}"
    assert any(expected in action for action in bindings[key]), key
for rule in (
    "floating_modifier Mod1 normal",
    "seat seat0 xcursor_theme Bibata-Modern-Ice 24",
    "seat seat0 hide_cursor 0",
    "gaps inner 6", "gaps outer 9",
    "# AWTARCHY-SWAY-OUTPUTS-BEGIN",
    "# AWTARCHY-SWAY-OUTPUTS-END",
):
    assert rule in CONFIG, rule
# Flat pointer profile must match Hyprland's raw-input default.
assert re.search(r"input type:pointer \{\s*accel_profile flat\s*pointer_accel 0\s*\}", CONFIG), (
    "Sway must explicitly disable libinput mouse acceleration")
assert "input type:touchpad {" in CONFIG

# Discrete Sway controls must honor the same Qt style configuration as
# Hyprland. Ly starts the root-owned wrapper, not a login shell, so theme
# variables must be exported before it launches the compositor.
SESSION_LAUNCH = (TRIAL / "session-launch.sh").read_text(encoding="utf-8")
for key, value in (
    ("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct"),
    ("QT6CT_PLATFORM_PLUGIN", "qt6ct"),
    ("GTK_THEME", "Materia-dark"),
    ("XCURSOR_THEME", "Bibata-Modern-Ice"),
):
    assert f"export {key}={value}" in SESSION_LAUNCH
# D-Bus activated apps must see the same dark theme as direct Sway exec.
SESSION = (TRIAL / "session.sh").read_text(encoding="utf-8")
assert "export QT_QPA_PLATFORMTHEME=qt5ct:qt6ct" in SESSION
assert "QT_QPA_PLATFORMTHEME" in SESSION
assert "QT6CT_PLATFORM_PLUGIN" in SESSION
assert 'session_environment[@]' in SESSION
assert CONFIG.count("QT_QPA_PLATFORMTHEME=qt5ct:qt6ct python3") == 2
assert 'session-wrapper-update.sh" apply "$repo"' in MANAGER
assert 'session-wrapper-update.sh" plan "$repo"' in MANAGER
assert "swaybg_command -" in CONFIG
assert "swaylock -f" not in CONFIG
assert "Mod4+Control+l exec swaylock" not in CONFIG
assert "swaylock" not in (TRIAL / "setup.sh").read_text()
assert "nwg-displays" in (TRIAL / "setup.sh").read_text()
sway_package_stage = RUNTIME.split(
    "install_sway_repo_dependencies_stage() {", 1
)[1].split("install_arch_repo_apps_stage()", 1)[0]
assert "swaylock" not in sway_package_stage
assert " mako " not in sway_package_stage
sway_manager_install = MANAGER.split(
    'if [[ "$operation" == install-sway ]]; then\n  for pkg in ', 1
)[1].split("; do", 1)[0]
assert "swaylock" not in sway_manager_install.split()
assert "mako" not in sway_manager_install.split()
assert "nwg-displays" in sway_manager_install.split()
assert 'include outputs' in CONFIG and 'include ../workspaces' in CONFIG
assert "toggle-utility.py hyprmoncfg" not in CONFIG
assert 'for_window [app_id="^nwg-displays$"] floating enable, resize set 85 ppt 90 ppt, move position center' in CONFIG
# Historical, explicitly owned swaylock remains eligible for removal,
# without removing anything the user installed independently.
assert "swaybg swayidle swaylock" in MANAGER
screencast = (TRIAL / "screencast-chooser.conf").read_text()
assert "chooser_type=dmenu" in screencast
assert "portal-chooser.py" in screencast
assert "chooser_cmd=fuzzel" not in screencast
assert '.config/xdg-desktop-portal-wlr/sway' in (TRIAL / "sync.py").read_text()

# Every Hyprland explicitly-floating utility must float in Sway on native
# Wayland and XWayland. Keep class/app_id rules exact to avoid floating games.
HYPRLAND = (ROOT / "config/hypr/hyprland.lua").read_text(encoding="utf-8")
floating_utility_sizes = {
    "btop": "80 ppt 85 ppt",
    "maccel": "90 ppt 96 ppt",
    "smtty": "50 ppt 65 ppt",
    "smtty-O": "50 ppt 65 ppt",
    "wallpicker": "85 ppt 90 ppt",
    "awtarchy-qalc": "347 px 510 px",
    "awtarchy-default-apps": "540 px 460 px",
    "Wiremix": "65 ppt 70 ppt",
    "org.pulseaudio.pavucontrol": "55 ppt 70 ppt",
    "Pulsemixer": "55 ppt 70 ppt",
    "hypr_quicksettings": "70 ppt 50 ppt",
    "awtarchy-tips-tui": "50 ppt 50 ppt",
    "hyprbars": "30 ppt 10 ppt",
}
for utility, geometry in floating_utility_sizes.items():
    hypr_class = utility.replace(".", "\\\\.")
    assert any(
        f'match = {{ class = "{pattern}" }}, float = true' in HYPRLAND
        for pattern in (f"^{hypr_class}$", f"^({hypr_class})$")
    ), "Hyprland reference removed or changed its floating class: " + utility
    sway_pattern = utility.replace(".", "[.]")
    for criterion in ("app_id", "class"):
        rule = (f'for_window [{criterion}="^{sway_pattern}$"] floating enable, '
                f'resize set {geometry}, move position center')
        assert rule in CONFIG, "Missing Sway floating parity: " + rule

# The Qt main window carries this exact upstream title, while dialogs have
# different titles. Match all ProtonUp-Qt children for floating, but never
# apply 45%-by-45% main-window sizing to each child window.
for criterion in ("app_id", "class"):
    assert (f'for_window [{criterion}="' +
            '^(net[.]davidotek[.]pupgui2|pupgui2|ProtonUp-Qt)$"] floating enable') in CONFIG
assert ('for_window [title="^ProtonUp-Qt( - Wine/Proton Installer)?$"] '
        'floating enable, resize set 45 ppt 45 ppt, move position center') in CONFIG
assert 'for_window [window_type="dialog"] floating enable' in CONFIG
assert 'for_window [window_role="^(dialog|pop-up|task_dialog)$"] floating enable' in CONFIG
for line in CONFIG.splitlines():
    if line.startswith("for_window ") and "floating enable" in line:
        assert '[app_id=".*"]' not in line and '[class=".*"]' not in line, (
            "Do not turn utility float parity into global app floating")

# Immediate page flips need output AND application permission; a fullscreen
# window remains required and ordinary desktop apps are not opted in.
assert "output * allow_tearing yes" in CONFIG
assert "output * max_render_time off" in CONFIG
assert re.search(r'(?m)^for_window \[app_id=.*steam_app_.*\] allow_tearing yes$', CONFIG)
assert re.search(r'(?m)^for_window \[class=.*steam_app_.*\] allow_tearing yes$', CONFIG)
assert 'for_window [app_id=".*"] allow_tearing yes' not in CONFIG
assert len(bindings) >= 70
assert "swayfx" not in CONFIG.lower()
# A native swaybar created during failed Quickshell startup was left visible
# even after the shell recovered; Mako also competed with Quickshell's own
# org.freedesktop.Notifications provider.
assert not re.search(r"(?m)^\s*bar\s*\{", CONFIG)
session = (TRIAL / "session.sh").read_text(encoding="utf-8")
assert "swaymsg bar mode dock" not in session
assert "mako >/dev/null" not in session
# Do not let Sway spawn its own solid-color swaybg over the user's
# per-monitor Awtwall/awww wallpaper on compositor reload.
assert re.search(r'(?m)^\\s*output\\s+[^#\\n]*\\s+(?:bg|background)\\s+', CONFIG) is None, (
    "Sway's output background must not compete with Awtwall")
assert 'awww-daemon' in session
assert 'awtwall --restore' in session
assert "swaybg_command -" in CONFIG


for path, fragments in (
    (TRIAL / "sway.desktop", ("Sway (Awtarchy Trial)",
      "Exec=/usr/local/bin/awtarchy-sway-session")),
    (TRIAL / "session-launch.sh", ("/usr/bin/sway --config", "XDG_CURRENT_DESKTOP=sway")),
    (TRIAL / "ipc.sh", ("awtarchy-sway", '[[ "$response" == "ok" ]]')),
    (TRIAL / "SwayBridge.qml", ("import Quickshell.I3", "I3.dispatch(")),
    (TRIAL / "session.sh", ("SWAYSOCK", "quickshell.sh")),
):
    data = path.read_text(encoding="utf-8")
    for fragment in fragments:
        assert fragment in data, (str(path), fragment)
for phrase in ("pacman -R --print", "pacman -R --noconfirm",
               "managed-packages", "update-sway", "install-hyprland",
               "remove-hyprland"):
    assert phrase in MANAGER, phrase
for prohibited in ("aur-scan install sway", "sway.portal"):
    assert prohibited not in MANAGER, prohibited
# A user-facing warning may name destructive options; only actual commands
# matter for preventing cascade or dependency-bypassing removal.
assert re.search(r"(?m)^\\s*(?:sudo\\s+)?pacman\\s+-R(?:ns|dd)(?:\\s|$)", MANAGER) is None

setup = (TRIAL / "setup.sh").read_text(encoding="utf-8")
match = re.search(r"^sources=\(([^)]*)\)$", setup, flags=re.MULTILINE)
assert match is not None
names = shlex.split(match.group(1))
assert len(names) == len(set(names))
assert "config" in names and "sway-portals.conf" in names
assert "toggle-utility.py" in names and "theme-colors.sh" in names
for name in names:
    assert name and "/" not in name and (TRIAL / name).is_file(), name
sync = (TRIAL / "sync.py").read_text(encoding="utf-8")
assert ".config/sway/awtarchy-trial/config" in sync

with tempfile.TemporaryDirectory(prefix="awtarchy-sway-ci-") as directory:
    temporary = Path(directory)
    shell = temporary / "awtarchy-sway"
    command(sys.executable, str(TRIAL / "render-quickshell.py"),
            "--source", str(ROOT / "config/quickshell/awtarchy"),
            "--dest", str(shell), "--bridge-dir", str(TRIAL))
    rendered = (shell / "shell.qml").read_text(encoding="utf-8")
    assert "ShellId awtarchy-sway" in rendered
    for path in shell.glob("*.qml"):
        data = path.read_text(encoding="utf-8")
        assert "import Quickshell.Hyprland" not in data, path.name
        assert '"hyprctl"' not in data, path.name
        assert "hl.dispatch(" not in data, path.name
    manager = temporary / "quickshell.sh"
    command(sys.executable, str(TRIAL / "render-manager.py"),
            "--source", str(ROOT / "config/hypr/scripts/quickshell.sh"),
            "--dest", str(manager))
    command("bash", "-n", str(manager))
    body = manager.read_text(encoding="utf-8")
    assert "quickshell-sway.log" in body
    assert "QUICKSHELL_CONFIG_NAME:-awtarchy-sway" in body
    assert "hyprctl" not in body

print("PASS: Sway installer isolation, binds, IPC, managed sources and Quickshell renderers")
