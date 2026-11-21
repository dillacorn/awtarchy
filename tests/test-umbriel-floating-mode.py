#!/usr/bin/env python3
"""Exercise Umbriel's persisted floating preference without compositor writes."""
import importlib.util
import os
import subprocess
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "compositors/umbriel/floating-windows.py"
spec = importlib.util.spec_from_file_location("umbriel_floating", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

with tempfile.TemporaryDirectory(prefix="umbriel-floating-check-") as tmp:
    root = Path(tmp)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    cfg = root / "config"
    target = cfg / "umbriel/awtarchy/floating-rules.toml"
    target.parent.mkdir(parents=True)
    target.write_bytes(mod.OFF)
    env = {"XDG_CONFIG_HOME": str(cfg), "XDG_RUNTIME_DIR": str(runtime),
           "XDG_CURRENT_DESKTOP": "Umbriel", "WAYLAND_DISPLAY": "wayland-1"}
    # The CLI (without --json) reports a successful reload with no stdout.
    # Prior code incorrectly tried json.loads("") and rolled back every time.
    reply = SimpleNamespace(stdout="", returncode=0)
    with patch.dict(os.environ, env), \
         patch.object(mod.os, "geteuid", return_value=1000), \
         patch.object(mod.subprocess, "run", return_value=reply) as run:
        mod.run(["status"])
        mod.run(["set", "on"])
        assert target.read_bytes() == mod.ON
        assert (runtime / "awtarchy-umbriel-floating-windows-state").read_text() == "enabled\\n".replace("\\n", "\n")
        assert [args.args[0][1:] for args in run.call_args_list] == [
            ["config", "validate"], ["msg", "config-reload"]]
        run.reset_mock()
        mod.run(["set", "off"])
        assert target.read_bytes() == mod.OFF
        assert len(run.call_args_list) == 2
        # A genuinely rejected reload must still restore the old file, and
        # must not publish "enabled" into Quickshell's runtime state.
        def reject_reload(argv, **kwargs):
            if argv == ["umbriel", "msg", "config-reload"] and kwargs.get("check"):
                raise subprocess.CalledProcessError(1, argv, stderr="reload refused")
            return reply

        with patch.object(mod.subprocess, "run", side_effect=reject_reload) as rejected:
            try:
                mod.run(["set", "on"])
            except subprocess.CalledProcessError:
                pass
            else:
                raise AssertionError("Rejected Umbriel reload was reported as success")
            assert [args.args[0][1:] for args in rejected.call_args_list] == [
                ["config", "validate"], ["msg", "config-reload"],
                ["msg", "config-reload"]]
        assert target.read_bytes() == mod.OFF
        assert (runtime / "awtarchy-umbriel-floating-windows-state").read_text() == "disabled\n"
        # A personalized file is never silently rewritten.
        target.write_text("# personal floating policy\n")
        try:
            mod.run(["set", "on"])
        except ValueError:
            pass
        else:
            raise AssertionError("Unexpected overwrite of a customized policy")
        assert target.read_text() == "# personal floating policy\n"

print("PASS: Umbriel native floating-only toggle, persistent state and custom preservation")
