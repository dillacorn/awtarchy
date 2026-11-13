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
assert "for package in sway swaybg swayidle swaylock xdg-desktop-portal-wlr" in RUNTIME
assert "sway via aur-scan" not in RUNTIME
assert "JayWM_Migration_Trial_Investigation" not in RUNTIME

bindings = {}
for line in CONFIG.splitlines():
    if line.startswith("bindsym "):
        _, key, action = line.split(maxsplit=2)
        bindings.setdefault(key, []).append(action)
for key, expected in {
    "Mod1+p": "ipc.sh launcher toggle",
    "Mod4+d": "ipc.sh launcher toggle",
    "Mod4+p": "ipc.sh powermenu begin",
    "Mod1+Tab": "focus next",
    "Mod1+Shift+Tab": "focus prev",
    "Mod1+Shift+b": "toggle-utility.py btop",
    "Mod4+Shift+b": "toggle-utility.py btop",
    "Mod4+t": "ipc.sh themes toggle",
    "Mod4+w": "toggle-utility.py wallpicker",
    "Mod4+Control+m": "toggle-utility.py hyprmoncfg",
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
    'for_window [app_id="btop"] floating enable',
    "# AWTARCHY-SWAY-OUTPUTS-BEGIN",
    "# AWTARCHY-SWAY-OUTPUTS-END",
):
    assert rule in CONFIG, rule
assert len(bindings) >= 70
assert "swayfx" not in CONFIG.lower()
# A native swaybar created during failed Quickshell startup was left visible
# even after the shell recovered; Mako also competed with Quickshell's own
# org.freedesktop.Notifications provider.
assert not re.search(r"(?m)^\s*bar\s*\{", CONFIG)
session = (TRIAL / "session.sh").read_text(encoding="utf-8")
assert "swaymsg bar mode dock" not in session
assert "mako >/dev/null" not in session

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
