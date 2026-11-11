#!/usr/bin/env python3
"""Regression checks for Sway Quickshell popups using layer-shell surfaces.

These checks prove the generated Sway shell does not expose its flyouts as
ordinary Sway tiled application windows. Live rendering still needs a real
Sway + Quickshell session.
"""
from pathlib import Path
import importlib.util
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
RENDERER = TRIAL / "render-quickshell.py"
UPSTREAM = ROOT / "config/quickshell/awtarchy"

spec = importlib.util.spec_from_file_location("sway_renderer", RENDERER)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)

expected = {
    "Launcher.qml": ("launcherWindow", "launcher", "requestedPlacement"),
    "ClipboardMenu.qml": ("clipboardWindow", "clipboard", "placement"),
    "Notifications.qml": ("centerWindow", "notifications", "placement"),
    "QuickSettings.qml": ("quickSettingsWindow", "quick-settings", "placement"),
    "NetworkMenu.qml": ("networkWindow", "network", "placement"),
    "BluetoothMenu.qml": ("bluetoothWindow", "bluetooth", "placement"),
    "BatteryMenu.qml": ("batteryWindow", "battery", "placement"),
}
assert renderer.SWAY_LAYER_FLYOUTS == expected
shell_helper = (TRIAL / "SwayFlyoutWindow.qml").read_text(encoding="utf-8")
for required in (
    "PanelWindow {",
    "WlrLayershell.layer: WlrLayer.Top",
    "WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand",
    "exclusionMode: ExclusionMode.Ignore",
    "anchors {",
    "left: true",
    "top: true",
    "margins {",
    "left: popup.offsetX",
    "top: popup.offsetY",
    'surfaceRole === "launcher"',
    'placement === "top"',
    'placement === "left"',
    "BarState.barSizeFor(",
):
    assert required in shell_helper, f"Layer-shell helper missing {required!r}"
assert "\nFloatingWindow {" not in shell_helper

with tempfile.TemporaryDirectory(prefix="awtarchy-sway-flyout-") as directory:
    output = Path(directory) / "awtarchy-sway"
    subprocess.run([
        sys.executable, str(RENDERER),
        "--source", str(UPSTREAM),
        "--dest", str(output),
        "--bridge-dir", str(TRIAL),
    ], check=True, timeout=40)

    assert (output / "SwayFlyoutWindow.qml").read_bytes() == (
        TRIAL / "SwayFlyoutWindow.qml").read_bytes()

    for filename, (window_id, role, placement) in expected.items():
        original = (UPSTREAM / filename).read_text(encoding="utf-8")
        rendered = (output / filename).read_text(encoding="utf-8")
        assert original.count("FloatingWindow {") == 1, filename
        assert rendered.count("SwayFlyoutWindow {") == 1, filename
        assert "FloatingWindow {" not in rendered, filename
        assert (
            f"    SwayFlyoutWindow {{\n"
            f"        id: {window_id}\n"
            f'        surfaceRole: "{role}"\n'
            f"        placement: root.{placement}\n"
        ) in rendered, filename
        # Awtarchy's common source for Hyprland must retain its original
        # toplevel type, instead of being mutated by Sway's renderer.
        assert "    FloatingWindow {" in original, filename
        assert "SwayFlyoutWindow" not in original, filename

    # Native notification popups already use layer-shell; only the
    # notification center should be replaced.
    notifications = (output / "Notifications.qml").read_text(encoding="utf-8")
    assert notifications.count("PanelWindow {") >= 1
    assert 'WlrLayershell.namespace: "awtarchy-notification-popup"' in notifications

    # The existing Quickshell prewarm and focus callbacks remain present.
    launcher = (output / "Launcher.qml").read_text(encoding="utf-8")
    assert "root.positionLauncher()" in launcher
    assert "search.forceActiveFocus();" in launcher
    assert "launcherWindow.visible = true;" in launcher

position = (TRIAL / "position.sh").read_text(encoding="utf-8")
assert "if [[ \"$action\" == prepare ]]" in position
assert "post-map floating or" in position
assert "swaymsg -r -t get_tree" not in position
assert "floating enable, resize" not in position
assert "move absolute position" not in position
assert "exit 0" in position

# The user updater gets the new component from the same generator and treats
# it as a managed file, not a symlink back into Hyprland's shell.
sync = (TRIAL / "sync.py").read_text(encoding="utf-8")
setup = (TRIAL / "setup.sh").read_text(encoding="utf-8")
assert "render-quickshell.py" in sync
assert "render-quickshell.py" in setup
assert '"$temp/awtarchy-sway/"*' in setup

print("PASS: seven Sway flyouts map directly as layer-shell, with no tiled intermediary")
