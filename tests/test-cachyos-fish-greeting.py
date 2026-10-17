#!/usr/bin/env python3
"""Regression tests for Awtarchy's CachyOS Fish greeting integration."""

from pathlib import Path
import os
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "local/share/awtarchy/cachyos-fish-greeting.py"
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
STOCK = (
    "source /usr/share/cachyos-fish-config/cachyos-config.fish\n"
    "\n# overwrite greeting\n# potentially disabling fastfetch\n"
    "\n#function fish_greeting\n# # smth smth\n#end\n"
)
VENDOR = (
    "## Run fastfetch as welcome message\n"
    "function fish_greeting\n    fastfetch\nend\n"
)


class CachyosFishGreetingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.fish_dir = self.home / ".config/fish"
        self.fish_dir.mkdir(parents=True)
        self.config = self.fish_dir / "config.fish"
        self.config.write_text(STOCK, encoding="utf-8")
        self.config.chmod(0o600)
        self.vendor = self.root / "vendor.fish"
        self.vendor.write_text(VENDOR, encoding="utf-8")

    def run_helper(self, shell="/usr/bin/fish"):
        return subprocess.run(
            [sys.executable, str(HELPER), "--home", str(self.home),
             "--vendor-config", str(self.vendor), "--shell", shell],
            text=True, capture_output=True, check=False,
        )

    def backups(self):
        return list(self.fish_dir.glob("config.fish.backup.*"))

    def test_stock_template_is_silenced_without_removing_fastfetch(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Disabled CachyOS", result.stdout)
        updated = self.config.read_text(encoding="utf-8")
        self.assertTrue(updated.startswith(STOCK))
        self.assertIn("function fish_greeting\nend\n", updated)
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(self.backups()[0].read_text(encoding="utf-8"), STOCK)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.backups()[0].stat().st_mode), 0o600)

    def test_idempotent_no_duplicate_or_new_backup(self):
        self.assertEqual(self.run_helper().returncode, 0)
        first = self.config.read_bytes()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_bytes(), first)
        self.assertEqual(len(self.backups()), 1)

    def test_custom_fish_greeting_is_preserved(self):
        custom = STOCK + "\nfunction fish_greeting\n  printf 'mine'\nend\n"
        self.config.write_text(custom, encoding="utf-8")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), custom)
        self.assertFalse(self.backups())

    def test_other_custom_commands_are_not_overridden(self):
        custom = STOCK + "\nalias ll 'ls -l'\n"
        self.config.write_text(custom, encoding="utf-8")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), custom)
        self.assertFalse(self.backups())

    def test_other_shell_and_missing_vendor_are_skipped(self):
        self.assertEqual(self.run_helper(shell="/bin/bash").returncode, 0)
        self.vendor.unlink()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), STOCK)
        self.assertFalse(self.backups())

    def test_vendor_without_expected_greeting_is_skipped(self):
        self.vendor.write_text("function fish_greeting\n  echo hi\nend\n", encoding="utf-8")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), STOCK)

    def test_unrelated_fish_config_is_skipped(self):
        self.config.write_text("echo hello\n", encoding="utf-8")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), "echo hello\n")
        self.assertFalse(self.backups())

    def test_symlinks_are_preserved(self):
        other = self.root / "custom.fish"
        other.write_text(STOCK, encoding="utf-8")
        self.config.unlink()
        self.config.symlink_to(other)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(other.read_text(encoding="utf-8"), STOCK)
        self.assertFalse(self.backups())

    def test_oversized_file_is_preserved(self):
        huge = STOCK + ("#" + "x" * 132000 + "\n")
        self.config.write_text(huge, encoding="utf-8")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), huge)

    def test_runtime_hooks_run_only_after_real_apply(self):
        runtime = RUNTIME.read_text(encoding="utf-8")
        helper_name = 'local/share/awtarchy/cachyos-fish-greeting.py'
        self.assertEqual(runtime.count(helper_name), 2)
        install = runtime.index("copy_awtarchy_configs_stage\n", runtime.index("run_install() {"))
        self.assertLess(install, runtime.index('cachyos_fish_helper="${REPO_DIR}/', install))
        update = runtime.index("if (( REVIEW_ONLY == 1 )); then", runtime.index("update_reset_backup_main() {"))
        audit = runtime.index('write_audit "$source_label" "$active_theme"', update)
        helper = runtime.index('cachyos_fish_helper="${repo_dir}/', audit)
        self.assertLess(update, audit)
        self.assertLess(audit, helper)
        self.assertIn('run_target env "HOME=${HOME_DIR}" python3 "$cachyos_fish_helper"', runtime)
        self.assertIn('run_as_target env "HOME=${HOME_DIR}" python3 - --home "$HOME_DIR" <"$cachyos_fish_helper"', runtime)


if __name__ == "__main__":
    unittest.main(verbosity=2)
