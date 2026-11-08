#!/usr/bin/env python3
"""Mango PolicyKit IPC targeting contract. Never tests or collects credentials."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/tui.py"
SPEC = importlib.util.spec_from_file_location("awtarchy_polkit_mango_tui", FILE)
tui = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = tui
SPEC.loader.exec_module(tui)

GOOD = {
    "id": 725,
    "pid": 1001,
    "appid": "awtarchy-polkit-agent",
    "title": "awtarchy-polkit-agent",
    "is_floating": False,
    "tags": [1],
}
MONITORS = {"monitors": [{"name": "DP-1", "active": True, "active_tags": [1]}]}


class MangoAuthTests(unittest.TestCase):
    def setUp(self):
        self.ui = object.__new__(tui.TerminalUI)
        self.requests = []
        self.env = mock.patch.dict(
            os.environ,
            {"XDG_CURRENT_DESKTOP": "mango",
             "MANGO_INSTANCE_SIGNATURE": "/run/user/1000/mango-test"},
        )
        self.env.start()
        self.addCleanup(self.env.stop)

        self.pid = mock.patch.object(tui.os, "getppid", return_value=1001)
        self.pid.start()
        self.addCleanup(self.pid.stop)
        self.exe = mock.patch.object(tui.os, "readlink", return_value="/usr/bin/foot")
        self.exe.start()
        self.addCleanup(self.exe.stop)

    def ipc(self, *args):
        self.requests.append(args)
        if args == ("get", "all-clients"):
            return {"clients": [dict(GOOD)]}
        if args == ("get", "all-monitors"):
            return MONITORS
        if args[0] == "dispatch":
            return {}
        self.fail("unexpected IPC request: " + str(args))

    def test_exact_window_is_focused_and_floated(self):
        with mock.patch.object(self.ui, "_mango", side_effect=self.ipc):
            self.assertEqual(self.ui._active_workspace(), "1")
            self.ui._move_window("1", True)
        self.assertEqual(self.requests, [
            ("get", "all-monitors"),
            ("get", "all-clients"),
            ("dispatch", "togglefloating", "client,725"),
            ("dispatch", "resizewin,900,520", "client,725"),
            ("dispatch", "centerwin", "client,725"),
            ("dispatch", "focusid", "client,725"),
        ])

    def test_window_on_another_tag_moves_to_current_tag(self):
        def other_tag(*args):
            if args == ("get", "all-clients"):
                return {"clients": [dict(GOOD, tags=[4])]}
            return self.ipc(*args)
        with mock.patch.object(self.ui, "_mango", side_effect=other_tag):
            self.ui._move_window("1", True)
        self.assertIn(("dispatch", "tag,1", "client,725"), self.requests)

    def test_foreign_app_with_matching_title_is_not_targeted(self):
        with mock.patch.object(self.ui, "_mango", return_value={
            "clients": [dict(GOOD, appid="untrusted-app")]}):
            with self.assertRaises(RuntimeError):
                self.ui._move_window("1", True)

    def test_foreign_pid_is_not_targeted(self):
        with mock.patch.object(self.ui, "_mango", return_value={
            "clients": [dict(GOOD, pid=2222)]}):
            with self.assertRaises(RuntimeError):
                self.ui._move_window("1", True)

    def test_untrusted_parent_executable_is_not_targeted(self):
        with mock.patch.object(tui.os, "readlink", return_value="/usr/bin/bash"):
            with mock.patch.object(self.ui, "_mango") as ipc:
                self.assertIsNone(self.ui._mango_window())
                ipc.assert_not_called()

    def test_duplicate_exact_windows_are_rejected(self):
        with mock.patch.object(self.ui, "_mango", return_value={
            "clients": [dict(GOOD), dict(GOOD, id=726)]}):
            self.assertIsNone(self.ui._mango_window())

    def test_malformed_monitor_tag_is_rejected(self):
        with mock.patch.object(self.ui, "_mango", return_value={
            "monitors": [{"active": True, "active_tags": [0]}]}):
            with self.assertRaises(RuntimeError):
                self.ui._active_workspace()

    def test_no_secret_is_sent_in_window_ipc(self):
        with mock.patch.object(self.ui, "_mango", side_effect=self.ipc):
            self.ui._move_window("1", True)
        self.assertTrue(all("secret" not in repr(args) for args in self.requests))

    def test_binary_ipc_error_fails_closed(self):
        with mock.patch.object(tui.subprocess, "run",
                               return_value=subprocess.CompletedProcess(
                                   ["mmsg"], 1, stdout='{"clients":[]}')):
            with self.assertRaises(RuntimeError):
                self.ui._mango("get", "all-clients")


if __name__ == "__main__":
    unittest.main()
