#!/usr/bin/env python3
"""Regression tests for Awtarchy's install/update GPU cursor policy."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace
from unittest import TestCase, main, mock
import tempfile


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "local/share/awtarchy/awtarchy-gpu-cursor.py"
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
spec = importlib.util.spec_from_file_location("awtarchy_gpu_cursor", HELPER)
assert spec and spec.loader
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)

MANAGED_CONFIG = """hl.config({
    general = { gaps_in = 6 },
    cursor = {
        sync_gsettings_theme = true,
        no_hardware_cursors = 2, -- managed default
        use_cpu_buffer = 2,
    },
})
"""


class GpuCursorPolicyTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sysfs = self.root / "sys" / "class" / "drm"
        self.sysfs.mkdir(parents=True)
        self.config = self.root / "hyprland.lua"
        self.config.write_text(MANAGED_CONFIG, encoding="utf-8")
        self.lspci = mock.patch.object(
            policy.subprocess, "run", return_value=SimpleNamespace(stdout="")
        )
        self.lspci.start()
        self.addCleanup(self.lspci.stop)

    def add_card(self, number, pci_vendor):
        device = self.sysfs / f"card{number}" / "device"
        device.mkdir(parents=True)
        (device / "vendor").write_text(pci_vendor + "\n", encoding="ascii")

    def assert_mode(self, expected):
        match = policy.cursor_mode_match(self.config.read_text(encoding="utf-8"))
        self.assertIsNotNone(match)
        self.assertEqual(match[2], str(expected))

    def test_nvidia_forces_software_cursor(self):
        self.add_card(0, "0x10de")
        gpu = policy.detect_gpu(self.sysfs)
        self.assertEqual(gpu, "nvidia")
        self.assertEqual(policy.apply_policy(self.config, gpu), "updated (2 -> 1)")
        self.assert_mode(1)
        self.assertEqual(policy.apply_policy(self.config, gpu), "unchanged (1)")

    def test_amd_and_intel_use_automatic_cursor(self):
        for vendor in ("0x1002", "0x8086"):
            with self.subTest(vendor=vendor):
                self.add_card(0, vendor)
                self.config.write_text(MANAGED_CONFIG.replace("= 2, --", "= 1, --"))
                gpu = policy.detect_gpu(self.sysfs)
                self.assertEqual(gpu, "other")
                policy.apply_policy(self.config, gpu)
                self.assert_mode(2)
                (self.sysfs / "card0" / "device" / "vendor").unlink()

    def test_hybrid_machine_with_nvidia_wins(self):
        self.add_card(0, "0x8086")
        self.add_card(1, "0x10de")
        self.assertEqual(policy.detect_gpu(self.sysfs), "nvidia")

    def test_pci_nvidia_caught_if_drm_only_exposes_intel(self):
        self.add_card(0, "0x8086")
        with mock.patch.object(
            policy.subprocess, "run",
            return_value=SimpleNamespace(
                stdout="01:00.0 3D controller: NVIDIA [10de:2d04]\n"
            ),
        ):
            self.assertEqual(policy.detect_gpu(self.sysfs), "nvidia")

    def test_unknown_hardware_preserves_existing_mode(self):
        fallback = self.root / "local.lua"
        fallback.write_text(MANAGED_CONFIG.replace("= 2, --", "= 1, --"))
        self.assertIsNone(policy.detect_gpu(self.sysfs))
        self.assertEqual(
            policy.apply_policy(self.config, None, fallback), "updated (2 -> 1)"
        )
        self.assert_mode(1)

    def test_unknown_hardware_without_fallback_does_not_guess(self):
        original = self.config.read_bytes()
        self.assertIn("skipped", policy.apply_policy(self.config, None))
        self.assertEqual(self.config.read_bytes(), original)

    def test_only_cursor_value_changes(self):
        self.add_card(0, "0x10de")
        policy.apply_policy(self.config, policy.detect_gpu(self.sysfs))
        self.assertEqual(
            self.config.read_text(encoding="utf-8"),
            MANAGED_CONFIG.replace("= 2, --", "= 1, --"),
        )

    def test_custom_nonliteral_cursor_policy_is_not_rewritten(self):
        self.config.write_text(MANAGED_CONFIG.replace(
            "no_hardware_cursors = 2,", "no_hardware_cursors = auto_mode,"
        ))
        original = self.config.read_bytes()
        self.assertIn("skipped", policy.apply_policy(self.config, "nvidia"))
        self.assertEqual(self.config.read_bytes(), original)

    def test_symlink_destination_is_rejected(self):
        target = self.root / "real.lua"
        target.write_text(MANAGED_CONFIG)
        self.config.unlink()
        self.config.symlink_to(target)
        with self.assertRaises(ValueError):
            policy.apply_policy(self.config, "nvidia")
        self.assertEqual(target.read_text(), MANAGED_CONFIG)

    def test_installer_and_updater_use_shared_helper_before_diff(self):
        runtime = RUNTIME.read_text(encoding="utf-8")
        self.assertIn(
            'run_as_target python3 - --config "\${HOME_DIR}/.config/hypr/hyprland.lua" <"$gpu_cursor_helper"',
            runtime,
        )
        staging = runtime.index(
            '--config "\${target_home}/.config/hypr/hyprland.lua"'
        )
        plan = runtime.index('build_plan "$target_home" "$plan_file"')
        self.assertLess(staging, plan)
        self.assertIn('--fallback "\${HOME_DIR}/.config/hypr/hyprland.lua"', runtime)


if __name__ == "__main__":
    main()
