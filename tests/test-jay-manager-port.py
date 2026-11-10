#!/usr/bin/env python3
"""Check that shared state and Jay manager don't invoke Hyprland in the new session."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "config/hypr/scripts/quickshell.sh"
TRIAL = ROOT / "trials/jay"
spec = importlib.util.spec_from_file_location("manager", TRIAL / "render-manager.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as temp:
    dst = Path(temp) / "quickshell.sh"
    module.render(SRC, dst)
    body = dst.read_text()
    assert "need hyprctl" not in body
    assert "hyprctl monitors" not in body
    assert "jay run-tagged awtarchy-jay-shell" in body
    assert "awtarchy-jay" in body
    assert body.count("monitor-info.py") >= 3
    try:
        module.render(SRC, dst)
    except ValueError:
        pass
    else:
        raise AssertionError("Would overwrite an existing manager")
print("PASS: Jay manager script render and privilege tags")
