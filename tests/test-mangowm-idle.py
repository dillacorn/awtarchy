#!/usr/bin/env python3
"""Validate Mango's focused idle IPC adapter without a graphical session."""
from pathlib import Path
import importlib.util
import json
import subprocess
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "config/mango/scripts/idle-ipc-compat.py"
SPEC = importlib.util.spec_from_file_location("awtarchy_mango_idle_ipc", TARGET)
assert SPEC and SPEC.loader
idle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(idle)

MONITORS = [
    {"name": "DP-1", "active": True, "active_tags": [3]},
    {"name": "HDMI-A-1", "active": False, "active_tags": [4]},
]
CLIENTS = [
    {"id": 21, "appid": "steam_app_1234", "title": "Game",
     "tags": [3], "is_visible": True, "is_minimized": False},
    {"id": 22, "appid": "com.github.IsmaelMartinez.teams_for_linux",
     "title": "Teams", "tags": [4], "is_minimized": False},
]


class IdleIpcTests(unittest.TestCase):
    def test_game_and_teams_are_exposed_to_existing_guard(self):
        with mock.patch.object(idle, "query", return_value={"clients": CLIENTS}):
            entries = idle.clients()
        self.assertEqual(entries[0]["class"], "steam_app_1234")
        self.assertEqual(entries[0]["workspace"]["id"], 3)
        self.assertTrue(entries[0]["mapped"])
        self.assertEqual(entries[1]["initialClass"],
                         "com.github.IsmaelMartinez.teams_for_linux")
        self.assertFalse(entries[0]["inhibitingIdle"])

    def test_active_and_visible_tags(self):
        with mock.patch.object(idle, "query", return_value={"monitors": MONITORS}):
            self.assertEqual(idle.active_tag(idle.active_monitor()), 3)
            with mock.patch("builtins.print") as emit:
                idle.main(["monitors", "-j"])
            shown = json.loads(emit.call_args.args[0])
            self.assertEqual([m["activeWorkspace"]["id"] for m in shown], [3, 4])
            with mock.patch("builtins.print") as emit:
                idle.main(["-j", "activeworkspace"])
            self.assertEqual(json.loads(emit.call_args.args[0])["id"], 3)

    def test_missing_mango_monitor_fails_closed(self):
        with mock.patch.object(idle, "query", return_value={"monitors": []}):
            with self.assertRaises(ValueError):
                idle.active_monitor()

    def test_unknown_operation_cannot_send_dispatch(self):
        with mock.patch.object(idle.subprocess, "run") as invoke:
            with self.assertRaises(ValueError):
                idle.main(["dispatch", "killactive"])
            invoke.assert_not_called()

    def test_dpms_targets_all_validated_monitors(self):
        with mock.patch.object(idle, "monitors", return_value=MONITORS):
            with mock.patch.object(idle.subprocess, "run", return_value=(
                    subprocess.CompletedProcess(["mmsg"], 0, stdout="{}")
            )) as invoke:
                idle.dpms("disable")
            self.assertEqual(invoke.call_args_list[0].args[0],
                             ["mmsg", "dispatch", "sleep_monitor,DP-1"])
            self.assertEqual(invoke.call_args_list[1].args[0],
                             ["mmsg", "dispatch", "sleep_monitor,HDMI-A-1"])

    def test_invalid_monitor_prevents_all_dpms_commands(self):
        invalid = [{"name": "DP-1"}, {"name": "bad,name"}]
        with mock.patch.object(idle, "monitors", return_value=invalid):
            with mock.patch.object(idle.subprocess, "run") as invoke:
                with self.assertRaises(ValueError):
                    idle.dpms("disable")
                invoke.assert_not_called()

    def test_ipc_errors_are_rejected(self):
        with mock.patch.object(idle.subprocess, "run", return_value=(
                subprocess.CompletedProcess(["mmsg"], 0, stdout='{"error":"offline"}'))):
            with self.assertRaises(ValueError):
                idle.query("all-clients")

    def test_session_contract(self):
        session = (ROOT / "config/mango/scripts/session.sh").read_text(encoding="utf-8")
        for delay in (60, 120, 180, 240, 540, 14400):
            self.assertIn(f"timeout {delay} ", session)
        self.assertIn("before-sleep", session)
        self.assertIn("MANGO_INSTANCE_SIGNATURE", (ROOT / "config/hypr/scripts/hypridle_action.sh").read_text())
        self.assertIn("SUSPEND_EXEC_OVERRIDE", (ROOT / "config/mango/scripts/idle.sh").read_text())
        self.assertIn("lock.sh", (ROOT / "config/mango/scripts/suspend-guard.sh").read_text())


if __name__ == "__main__":
    unittest.main()
