#!/usr/bin/env python3
"""Test Mango cursor migration without modifying the installed Awtarchy tree."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("mango_cursor", ROOT / "config/mango/scripts/cursor-variant.py")
cursor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cursor)


class CursorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = pathlib.Path(self.tmp.name)
        self.config = base / "config.conf"
        self.state = base / "state.json"
        self.content = "tag_num=10\nenv=XCURSOR_THEME,Bibata-Modern-Ice\nenv=XCURSOR_SIZE,24\ncursor_size=24\ncursor_theme=Bibata-Modern-Ice\n"
        self.config.write_text(self.content, encoding="utf-8")
        self.config.chmod(0o640)

    def test_saved_variant_and_idempotence(self):
        self.state.write_text(json.dumps({"cursor_variant": "classic-right"}), encoding="utf-8")
        chosen = cursor.requested_theme(self.state)
        self.assertEqual(chosen, "Bibata-Modern-Classic-Right")
        self.assertTrue(cursor.update_config(self.config, chosen, True))
        self.assertFalse(cursor.update_config(self.config, chosen, True))
        self.assertIn("env=XCURSOR_THEME,Bibata-Modern-Classic-Right", self.config.read_text())
        self.assertIn("cursor_theme=Bibata-Modern-Classic-Right", self.config.read_text())
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)

    def test_actual_mango_config_accepts_saved_cursor_choice(self):
        # Regression for duplicated compositor and environment cursor keys.
        sample = (ROOT / "config/mango/config.conf").read_text(encoding="utf-8")
        self.config.write_text(sample, encoding="utf-8")
        self.state.write_text(json.dumps({"cursor_variant": "amber-sharp"}), encoding="utf-8")
        self.assertTrue(cursor.update_config(
            self.config, cursor.requested_theme(self.state), True))
        updated = self.config.read_text(encoding="utf-8")
        self.assertEqual(updated.count("cursor_theme=Bibata-Original-Amber"), 1)
        self.assertEqual(updated.count("env=XCURSOR_THEME,Bibata-Original-Amber"), 1)
        self.assertEqual(updated.count("cursor_size=24"), 1)
        self.assertEqual(updated.count("env=XCURSOR_SIZE,24"), 1)

    def test_state_missing_defaults_to_ice(self):
        self.assertEqual(cursor.requested_theme(self.state), "Bibata-Modern-Ice")
        self.assertFalse(cursor.update_config(self.config, cursor.THEMES["ice"], True))

    def test_invalid_preference_refuses_mutation(self):
        self.state.write_text('{"cursor_variant":"spoofed"}', encoding="utf-8")
        with self.assertRaises(ValueError):
            cursor.requested_theme(self.state)
        self.assertEqual(self.config.read_text(), self.content)

    def test_duplicate_cursor_env_refuses_mutation(self):
        self.config.write_text(self.content + "env=XCURSOR_THEME,Bibata-Modern-Ice\n")
        with self.assertRaises(ValueError):
            cursor.update_config(self.config, cursor.THEMES["classic"], True)

    def test_linked_config_refuses_mutation(self):
        link = self.config.parent / "linked.conf"
        link.symlink_to(self.config)
        with self.assertRaises(ValueError):
            cursor.update_config(link, cursor.THEMES["classic"], True)
        self.assertEqual(self.config.read_text(), self.content)


if __name__ == "__main__":
    unittest.main()
