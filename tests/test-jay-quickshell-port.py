#!/usr/bin/env python3
"""Isolated rendering and source/QML contracts. Not a live session test."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "config/quickshell/awtarchy"
TRIAL = ROOT / "trials/jay"

spec = importlib.util.spec_from_file_location("jay_renderer", TRIAL / "render-quickshell.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)

def check():
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / "awtarchy-jay"
        renderer.render(SRC, target, TRIAL)
        files = sorted(target.glob("*.qml"))
        assert len(files) >= len(list(SRC.glob("*.qml")))
        assert (target / "JayBridge.qml").is_file()
        assert (target / "JayFocusGrab.qml").is_file()
        assert "not available" in (target / "ScreenShareGuardCard.qml").read_text().lower()
        assert "screenshare_guard.sh" not in (target / "ScreenShareGuardCard.qml").read_text()
        assert "JayBridge.activateWorkspace" in (target / "Bar.qml").read_text()
        bar = (target / "Bar.qml").read_text()
        assert "/jay/awtarchy-trial/mode-help.sh" in bar
        assert "toggle_mouse_submap.sh" not in bar
        assert 'JayBridge.moveWorkspace(arrowSlot.modelData.dir)' in bar
        assert 'JayBridge.moveWorkspace(arrowSlotVertical.modelData.dir)' in bar
        assert 'names = { u: "up", d: "down", l: "left", r: "right" }' in (target / "JayBridge.qml").read_text()
        quick = (target / "QuickSettings.qml").read_text()
        assert 'visible: root.quickSettingsSectionVisible("display-effects")' not in quick
        assert 'visible: root.quickSettingsSectionVisible("submap")' not in quick
        assert 'visible: root.quickSettingsSectionVisible("numlock")' not in quick
        numlock = (target / "NumlockSessionTweak.qml").read_text()
        assert "readonly property bool enabled: false" in numlock
        assert "hyprctl" not in numlock and '"false"' not in numlock
        assert "/jay/awtarchy-trial/lock.sh" in (target / "PowerMenu.qml").read_text()
        assert "toggleDefaultApps(): void" in (target / "shell.qml").read_text()
        assert "/jay/awtarchy-trial/default-apps.sh" in (target / "QuickSettings.qml").read_text()
        assert 'JayBridge.toggleUtility("Wiremix"' in (target / "Bar.qml").read_text()
        assert "wiremix-toggle.sh" not in (target / "Bar.qml").read_text()
        assert "import Quickshell.WindowManager" in (target / "JayBridge.qml").read_text()
        assert "import Quickshell.Hyprland" not in "\n".join(p.read_text() for p in files)
        for p in files:
            assert '"hyprctl"' not in p.read_text(), p.name
        assert (SRC / "shell.qml").read_bytes() != (target / "shell.qml").read_bytes()
        # A second invocation must not destroy an existing user-specific profile.
        try:
            renderer.render(SRC, target, TRIAL)
        except ValueError:
            pass
        else:
            raise AssertionError("Renderer overwrote an existing profile")

if __name__ == "__main__":
    check()
    print("PASS: isolated Jay QML generation and generic Wayland bridge")
