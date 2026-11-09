#!/usr/bin/env python3
"""Monitor-rule migration tests with synthetic sources; never change real displays."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
IMPORTER = ROOT / "config/mango/scripts/import-hypr-monitors.py"
PROFILE = ROOT / "trials/mangowm/monitor-profiles/gaming-dual-1080p.conf"
CONFIG = ROOT / "config/mango/config.conf"
spec = importlib.util.spec_from_file_location("mango_monitor_importer", IMPORTER)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)

HYPR = '''
-- The active source is real Hyprland Lua, not a generated Mango file.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", vrr = 0 })
-- hl.monitor({ output = "DP-6", mode = "1920x1080@1", position = "1x1", scale = 1 })
hl.monitor({ output = "DP-3", mode = "1920x1080@240", position = "0x-1080", scale = 1, vrr = 0 })
hl.monitor({ output = "DP-1", mode = "1920x1080@400", position = "0x0", scale = 1, vrr = 0 })
hl.monitor({ output = "Virtual-1", mode = "1600x900@60", position = "auto", scale = 1, vrr = 0 })
'''


class MangoMonitorImportTests(unittest.TestCase):
    def test_normalizes_negative_hyprland_coordinates(self):
        monitors, skipped = importer.parse_monitors(HYPR)
        self.assertEqual([m["name"] for m in monitors], ["DP-3", "DP-1"])
        self.assertEqual(skipped, ["Virtual-1"])
        output = importer.rule_lines(monitors, "DP-1")
        self.assertIn("name:^DP-3$,width:1920,height:1080,refresh:240,x:0,y:0,scale:1,vrr:0", output)
        self.assertIn("name:^DP-1$,width:1920,height:1080,refresh:400,x:0,y:1080,scale:1,vrr:0,primary:1", output)
        self.assertNotIn("y:-", output)
        self.assertNotIn("DP-6", output)
        self.assertEqual(PROFILE.read_text().splitlines()[-2:], output.splitlines()[-2:])

    def test_no_guessing_or_dynamic_lua(self):
        for source in (
            'hl.monitor({ output = "DP-1", mode = "auto", position = "0x0", scale = 1 })',
            'hl.monitor(config.profile)',
            'hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = math.random() })',
            'hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = 1, unknown = 1 })',
        ):
            with self.subTest(source=source), self.assertRaises(importer.ProfileError):
                importer.parse_monitors(source)

    def test_invalid_or_duplicate_modes_are_rejected(self):
        for invalid in ("10", "10000", "0"):
            src = HYPR.replace("1920x1080@240", "1920x1080@" + invalid)
            with self.subTest(refresh=invalid), self.assertRaises(importer.ProfileError):
                importer.parse_monitors(src)
        with self.assertRaises(importer.ProfileError):
            importer.parse_monitors(HYPR.replace('"DP-1"', '"DP-3"'))
        screens, _ = importer.parse_monitors(HYPR)
        with self.assertRaises(importer.ProfileError):
            importer.rule_lines(screens, "DP-7")

    def test_file_creation_fails_closed(self):
        screens, _ = importer.parse_monitors(HYPR)
        generated = importer.rule_lines(screens, "DP-1")
        with tempfile.TemporaryDirectory() as root:
            rootdir = Path(root)
            dest = rootdir / "monitors-local.conf"
            importer.apply_new_file(dest, generated)
            self.assertEqual(dest.read_text(), generated)
            self.assertEqual(dest.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(importer.ProfileError):
                importer.apply_new_file(dest, "SHOULD-NOT-REPLACE")
            self.assertEqual(dest.read_text(), generated)
            symlink = rootdir / "monitor-link.conf"
            symlink.symlink_to(dest)
            with self.assertRaises(importer.ProfileError):
                importer.apply_new_file(symlink, "SHOULD-NOT-REPLACE")
            self.assertEqual(dest.read_text(), generated)

    def test_preview_only_does_not_write(self):
        with tempfile.TemporaryDirectory() as root:
            rootdir = Path(root)
            src = rootdir / "hyprland.lua"
            src.write_text(HYPR)
            dst = rootdir / "monitors-local.conf"
            preview = subprocess.run(
                [sys.executable, str(IMPORTER), "--source", str(src),
                 "--output", str(dst), "--primary", "DP-1"],
                capture_output=True, text=True, check=True)
            self.assertIn("refresh:240", preview.stdout)
            self.assertFalse(dst.exists())
            created = subprocess.run(
                [sys.executable, str(IMPORTER), "--source", str(src),
                 "--output", str(dst), "--primary", "DP-1", "--apply"],
                capture_output=True, text=True, check=True)
            self.assertEqual(dst.read_text(), preview.stdout)
            self.assertIn("Created:", created.stderr)

    def test_optional_source_is_not_global_managed_overwrite(self):
        lines = CONFIG.read_text().splitlines()
        self.assertEqual(lines.count(
            "source_optional=~/.config/mango/monitors-local.conf"), 1)
        self.assertNotIn("monitor_rule=name:^DP-1$", CONFIG.read_text())
        self.assertNotIn("monitor_rule=name:^DP-3$", CONFIG.read_text())


if __name__ == "__main__":
    unittest.main()
