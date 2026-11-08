#!/usr/bin/env python3
"""Mango floating utility toggle: exact-ID targeting and safe fallback."""
import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/mango/scripts/launch-handler.py"
SPEC = importlib.util.spec_from_file_location("mango_launch_handler", SOURCE)
handler = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = handler
SPEC.loader.exec_module(handler)

ACTIVE = {"monitors": [
    {"name": "DP-1", "active": True, "active_tags": [2]},
    {"name": "DP-2", "active": False, "active_tags": [4]},
]}


class MangoToggleTests(unittest.TestCase):
    def setUp(self):
        env = mock.patch.dict(os.environ,
            {"MANGO_INSTANCE_SIGNATURE": "/run/user/test/mango",
             "XDG_CURRENT_DESKTOP": "mango",
             "APP_NO_LAUNCH_IF_TILED": "0",
             "APP_CLASS_OVERRIDE": "awtarchy-default-apps",
             "APP_TITLE_OVERRIDE": "awtarchy-default-apps"})
        env.start()
        self.addCleanup(env.stop)
        self.calls = []
        self.spawns = []
        self.clients = []

        def ipc(*args):
            self.calls.append(args)
            if args == ("get", "all-monitors"):
                return ACTIVE
            if args == ("get", "all-clients"):
                return {"clients": self.clients}
            if args[:2] == ("dispatch", "killclient"):
                return {}
            raise AssertionError("Unexpected Mango IPC " + str(args))

        patcher = mock.patch.object(handler, "ipc", side_effect=ipc)
        patcher.start()
        self.addCleanup(patcher.stop)
        starter = mock.patch.object(handler, "launch",
            side_effect=lambda command: self.spawns.append(command))
        starter.start()
        self.addCleanup(starter.stop)
        timer = mock.patch.object(handler.time, "sleep", return_value=None)
        timer.start()
        self.addCleanup(timer.stop)

    def client(self, cid, monitor="DP-1", tags=None, floating=True,
               appid="awtarchy-default-apps", title="awtarchy-default-apps"):
        return {"id": cid, "appid": appid, "title": title,
            "is_floating": floating, "is_minimized": False,
            "monitor": monitor, "tags": [2] if tags is None else tags,
            "pid": 2026}

    def test_toggle_closes_only_exact_visible_client(self):
        self.clients = [
            self.client(9, monitor="DP-2", tags=[4]),
            self.client(10),
            self.client(11, appid="unrelated", title="awtarchy-default-apps"),
        ]
        handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertIn(("dispatch", "killclient", "client,10"), self.calls)
        self.assertNotIn(("dispatch", "killclient", "client,9"), self.calls)
        self.assertNotIn(("dispatch", "killclient", "client,11"), self.calls)
        self.assertEqual(self.spawns, [])

    def test_remote_closes_and_opens_here(self):
        self.clients = [self.client(9, monitor="DP-2", tags=[4])]
        handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertIn(("dispatch", "killclient", "client,9"), self.calls)
        self.assertEqual(self.spawns, ["foot --app-id awtarchy-default-apps"])

    def test_tiled_window_never_closed_or_duplicated_if_protected(self):
        os.environ["APP_NO_LAUNCH_IF_TILED"] = "1"
        self.clients = [self.client(10, floating=False)]
        handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertFalse(any(c[0] == "dispatch" for c in self.calls))
        self.assertEqual(self.spawns, [])

    def test_foreign_title_with_different_app_id_is_not_closed(self):
        self.clients = [self.client(11, appid="unrelated", title="awtarchy-default-apps")]
        handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertFalse(any(c[0] == "dispatch" for c in self.calls))
        self.assertEqual(len(self.spawns), 1)

    def test_missing_monitor_refuses_mutation(self):
        with mock.patch.object(handler, "ipc", return_value={"monitors": []}):
            with self.assertRaises(RuntimeError):
                handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertEqual(self.spawns, [])

    def test_not_mango_refuses_mutation(self):
        with mock.patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Hyprland"}):
            with self.assertRaises(RuntimeError):
                handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertEqual(self.calls, [])
        self.assertEqual(self.spawns, [])

    def test_invalid_client_id_never_closed(self):
        self.clients = [self.client(0), self.client(True)]
        handler.toggle("awtarchy-default-apps", "foot --app-id awtarchy-default-apps")
        self.assertFalse(any(c[0] == "dispatch" for c in self.calls))
        self.assertEqual(len(self.spawns), 1)


if __name__ == "__main__":
    unittest.main()
