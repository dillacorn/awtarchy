#!/usr/bin/env python3
"""Read-only simulation of Mango 0.18.5 IPC geometry and client targeting."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "awtarchy_mango_position", ROOT / "config/mango/scripts/position.py")
position = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(position)


class PositionTests(unittest.TestCase):
    def setUp(self):
        self.actions = []
        self.monitors = [
            {"name": "DP-1", "x": 0, "y": 0, "width": 1920, "height": 1080},
            {"name": "DP-2", "x": 1920, "y": 0, "width": 1600, "height": 900},
        ]
        self.client = {
            "id": 143, "pid": 456,
            "title": "Awtarchy Application Search",
            "monitor": "DP-1", "tags": [1],
            "width": 420, "height": 582,
            "x": 10, "y": 15, "is_floating": True,
        }

        def get(kind):
            if kind == "all-monitors":
                return {"monitors": self.monitors}
            if kind == "all-clients":
                return {"clients": [self.client]}
            raise AssertionError(kind)

        self.patches = [
            mock.patch.object(position, "query", side_effect=get),
            mock.patch.object(position, "quickshell_pid", return_value=True),
            mock.patch.object(position, "state", return_value={
                "launcher_sizes": {"DP-1": {
                    "width": 500, "height": 600, "saved": True, "save_version": 2}},
                "monitors": {"DP-1": {"bar_size": 28}},
            }),
            mock.patch.object(position, "prepared_target", return_value=None),
            mock.patch.object(position, "cmd", side_effect=self.capture),
        ]
        for patch in self.patches:
            patch.start()
        self.addCleanup(lambda: [patch.stop() for patch in reversed(self.patches)])

    def capture(self, *args):
        self.actions.append(args)
        return None

    def test_saved_center_geometry(self):
        position.reposition("launcher", "DP-1", "center", "spawn")
        self.assertIn(("dispatch", "resizewin,500,600", "client,143"), self.actions)
        self.assertIn(("dispatch", "movewin,710,240", "client,143"), self.actions)
        self.assertFalse(any(args[1] == "togglefloating" for args in self.actions))

    def test_target_exact_pid_and_monitor(self):
        self.client["is_floating"] = False
        position.reposition("launcher", "DP-2", "top", "spawn")
        self.assertIn(("dispatch", "tagmon,DP-2,1", "client,143"), self.actions)
        self.assertIn(("dispatch", "togglefloating", "client,143"), self.actions)

    def test_launcher_tracks_bottom_bar_after_stale_top_prewarm(self):
        self.monitors[0]["y"] = 1080
        with mock.patch.object(position, "state", return_value={
            "monitors": {"DP-1": {"position": "bottom", "bar_size": 28}},
        }), mock.patch.object(position, "prepared_target",
                             return_value=("DP-1", "top-center")):
            position.reposition("launcher", "DP-1", "top-center", "spawn")
        # 1080+1080 - 28px bar - 582px launcher = 1550.
        self.assertIn(("dispatch", "movewin,750,1550", "client,143"),
                      self.actions)
        self.assertFalse(any("movewin,750,1108" in str(value)
                             for value in self.actions))

    def test_launcher_honors_current_edge_and_requested_center(self):
        config = {"monitors": {"DP-1": {"position": "bottom"}}}
        self.assertEqual(position.launcher_edge_from_state(
            "DP-1", "top-center", config), "bottom-center")
        self.assertEqual(position.launcher_edge_from_state(
            "DP-1", "top", config), "bottom")
        self.assertEqual(position.launcher_edge_from_state(
            "DP-1", "center", config), "center")
        self.assertEqual(position.launcher_edge_from_state(
            "DP-2", "top-center", config), "top-center")

    def test_launcher_ignores_prepared_target_from_other_output(self):
        with mock.patch.object(position, "prepared_target",
                             return_value=("DP-2", "top-center")):
            position.reposition("launcher", "DP-1", "bottom-center", "spawn")
        self.assertIn(("dispatch", "movewin,710,452", "client,143"),
                      self.actions)
        self.assertFalse(any(args[1].startswith("tagmon,")
                             for args in self.actions))

    def test_invalid_action_fails_without_dispatch(self):
        with self.assertRaises(ValueError):
            position.reposition("launcher", "DP-1", "center", "bogus")
        self.assertEqual(self.actions, [])

    def test_prepare_validation(self):
        with tempfile.TemporaryDirectory() as root:
            with mock.patch.object(position, "PREPARED", pathlib.Path(root) / "prepared"):
                with self.assertRaises(ValueError):
                    position.prepare(["launcher", "DP-1", "center",
                                      "0", "500", "28", "-1", "1920", "1080"])
                position.prepare(["launcher", "DP-1", "center",
                                  "420", "582", "28", "-1", "1920", "1080"])
                self.assertEqual(
                    (position.PREPARED / "launcher").read_text(),
                    "DP-1\tcenter\n")


if __name__ == "__main__":
    unittest.main()
