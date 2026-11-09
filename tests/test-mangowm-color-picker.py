#!/usr/bin/env python3
"""Test Mango's pixel picker without touching a real display or clipboard."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/mango/scripts/color-picker.py"
spec = importlib.util.spec_from_file_location("mango_color_picker", SCRIPT)
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)


class PixelPickerTests(unittest.TestCase):
    def test_one_pixel_rgb(self):
        ppm = b"P6\n1 1\n255\n" + bytes((1, 20, 255))
        self.assertEqual(picker.ppm_color(ppm), "#0114ff")
        # A pixel starting with whitespace or a hash is binary image data,
        # not another header token.
        self.assertEqual(picker.ppm_color(b"P6\n1 1\n255\n\n #"), "#0a2023")

    def test_comments_and_malformed_files(self):
        self.assertEqual(picker.ppm_color(
            b"P6\n# viewport\n1 1\n255\n" + bytes((0, 80, 4))), "#005004")
        for corrupt in (b"", b"P3\n1 1\n255\n123", b"P6\n1 1\n255\n",
                        b"P6\n1 1\n65535\n\x00\x00\x00",
                        b"P6\n999 999\n255\n\x00\x00\x00"):
            with self.subTest(ppm=corrupt), self.assertRaises(ValueError):
                picker.ppm_color(corrupt)

    def test_capture_and_clipboard_exact_hex(self):
        calls = []

        def simulate(argv, **kwargs):
            calls.append(argv)
            if argv[:1] == ["slurp"]:
                return subprocess.CompletedProcess(argv, 0, stdout="12,24 1x1\n")
            if argv[:1] == ["grim"]:
                return subprocess.CompletedProcess(argv, 0,
                    stdout=b"P6\n1 1\n255\n\x10\x20\x30")
            if argv[:1] == ["wl-copy"]:
                self.assertEqual(kwargs["input"], "#102030")
                return subprocess.CompletedProcess(argv, 0)
            raise AssertionError("Unexpected subprocess " + repr(argv))

        with mock.patch.object(picker.subprocess, "run", side_effect=simulate), \
                mock.patch.object(picker.Path, "is_file", return_value=False):
            self.assertEqual(picker.main(), 0)
        self.assertEqual(calls, [
            ["slurp", "-p"], ["grim", "-g", "12,24 1x1", "-t", "ppm", "-"],
            ["wl-copy"]
        ])

    def test_cancel_does_not_change_clipboard(self):
        with mock.patch.object(picker.subprocess, "run",
            side_effect=subprocess.CalledProcessError(1, ["slurp", "-p"])) as run:
            self.assertEqual(picker.main(), 0)
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
