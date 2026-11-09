#!/usr/bin/env python3
"""Verify rendered Mango-only bar controls, animation pacing and float rules."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANGO = (ROOT / "config/mango/config.conf").read_text(encoding="utf-8")
BRIDGE = (ROOT / "trials/mangowm/MangoBridge.qml").read_text(encoding="utf-8")
HYPR = (ROOT / "config/hypr/hyprland.lua").read_text(encoding="utf-8")


def options():
    found = {}
    for line in MANGO.splitlines():
        if line and not line.startswith("#") and "=" in line:
            name, value = line.split("=", 1)
            found.setdefault(name, []).append(value)
    return found


class MangoUIParityTests(unittest.TestCase):
    def test_native_mode_updates_bar_without_hyprland_file(self):
        self.assertIn('command: ["mmsg", "watch", "keymode"]', BRIDGE)
        self.assertIn('root.keyMode = value;', BRIDGE)
        self.assertIn('if (!keymodeEvents.running)', BRIDGE)
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / "awtarchy-mango"
            subprocess.run(
                [sys.executable, str(ROOT / "trials/mangowm/render-quickshell.py"),
                 "--source", str(ROOT / "config/quickshell/awtarchy"),
                 "--dest", str(dest),
                 "--bridge-dir", str(ROOT / "trials/mangowm")],
                check=True, capture_output=True, text=True)
            bar = (dest / "Bar.qml").read_text(encoding="utf-8")
            self.assertIn('MangoBridge.keyMode === "default" ? ""', bar)
            self.assertIn('visible: bar.mangoModeLabel.length > 0', bar)
            self.assertIn('bar.mouseSubmapScript, "toggle", "mouse"', bar)
            self.assertIn('bar.mouseSubmapScript, "set", "default"', bar)
            self.assertIn('configHome + "/mango/scripts/keymode.sh"', bar)
            self.assertNotIn('submapFile', bar)
            self.assertNotIn('awtarchy-hypr-submap', bar)

    def test_fast_animation_timing_and_invisible_drop_overlay(self):
        conf = options()
        targets = {
            "animations": 0,
            "animation_duration_move": 110,
            "animation_duration_open": 120,
            "animation_duration_tag": 0,
            "animation_duration_close": 90,
            "animation_duration_focus": 0,
        }
        for key, target in targets.items():
            with self.subTest(key=key):
                self.assertEqual(conf[key], [str(target)])
        self.assertEqual(conf["drop_color"], ["0x00000000"])
        self.assertEqual(conf["drag_tile_to_tile"], ["1"])
        self.assertEqual(conf["drag_tile_small"], ["0"])

    def test_floating_app_parity(self):
        app_patterns = [
            "awtarchy-qalc", "awtarchy-default-apps",
            "org.pulseaudio.pavucontrol", "Pulsemixer", "Wiremix",
            "hypr_quicksettings", "awtarchy-tips-tui", "maccel",
            "smtty", "smtty-O", "wallpicker", "net.davidotek.pupgui2",
            "btop",
        ]
        rules = [line.split("=", 1)[1] for line in MANGO.splitlines()
                 if line.startswith("window_rule=")]
        for app in app_patterns:
            with self.subTest(app=app):
                matched = [
                    rule for rule in rules if "is_floating:1" in rule
                    and "app_id:" in rule
                    and re.search(rule.split("app_id:", 1)[1].split(",", 1)[0],
                                  app)
                ]
                self.assertTrue(matched, f"No Mango floating rule for {app}")
                self.assertTrue(app in HYPR or app.replace(".", r"\\.") in HYPR)
        for pattern in ("Open File", "Select a File", "Choose wallpaper",
                        "Open Folder", "Save As", "Library", "File Upload"):
            self.assertTrue(any("is_floating:1" in rule
                                and "title:" in rule and pattern in rule
                                for rule in rules), pattern)
        self.assertTrue(any("is_global:1" in rule and
                            "title:^[Pp]icture" in rule for rule in rules))
        self.assertTrue(any("is_floating:0" in rule and
                            "Friends List" in rule for rule in rules))


if __name__ == "__main__":
    unittest.main()
