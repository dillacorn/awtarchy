#!/usr/bin/env python3
"""Prevent Sway update regressions that omit newly required generated QML.

This stages a complete, isolated fake home and real renderer output. It does
not modify the developer's actual Sway, Hyprland, or Quickshell files.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "trials/sway/sync.py"
sys.path.insert(0, str(SYNC.parent))
import sync as sway_sync

def digest(data):
    return hashlib.sha256(data).hexdigest()

with tempfile.TemporaryDirectory(prefix="sway-update-test-") as tmp:
    base = Path(tmp)
    home = base / "home"
    home.mkdir()
    state = home / ".local/state/awtarchy"
    state.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="sway-render-test-") as stage:
        desired = sway_sync.expected_files(ROOT, home, Path(stage))

    missing = home / ".config/quickshell/awtarchy-sway/SwayFlyoutWindow.qml"
    assert missing in desired, "Sway renderer must provide a layer-shell popup module"
    baseline = {}
    for path, contents in desired.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if path == missing:
            continue
        path.write_bytes(contents)
        baseline[str(path.relative_to(home))] = digest(contents)
    manifest = state / "sway-managed-baseline.json"
    manifest.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")

    env = os.environ.copy()
    env["HOME"] = str(home)
    def run(mode):
        result = subprocess.run(
            [sys.executable, str(SYNC), mode, "--repo", str(ROOT)],
            env=env, capture_output=True, text=True, timeout=50)
        assert result.returncode == 0, result.stdout + "\n" + result.stderr
        return result.stdout

    report = run("review")
    assert "WOULD INSTALL: .config/quickshell/awtarchy-sway/SwayFlyoutWindow.qml" in report, report
    assert not missing.exists()
    applied = run("apply")
    assert "INSTALL: .config/quickshell/awtarchy-sway/SwayFlyoutWindow.qml" in applied, applied
    assert missing.read_bytes() == desired[missing]
    updated = json.loads(manifest.read_text())
    key = str(missing.relative_to(home))
    assert updated[key] == digest(desired[missing])

    # Manually installed exact source from an earlier broken updater must be
    # adopted into the baseline without rewriting the user's copy.
    updated.pop(key)
    manifest.write_text(json.dumps(updated, indent=2) + "\n")
    stamp = missing.stat().st_mtime_ns
    assert "WOULD ADOPT: " + key in run("review")
    assert "ADOPT: " + key in run("apply")
    assert missing.stat().st_mtime_ns == stamp
    assert json.loads(manifest.read_text())[key] == digest(desired[missing])

    # If the user edits their managed QML, the updater must never overwrite.
    missing.write_bytes(b"// personal Sway QML modification\n")
    report = run("apply")
    assert "PRESERVE modified file: " + key in report, report
    assert missing.read_bytes() == b"// personal Sway QML modification\n"

print("PASS: missing generated Sway QML install, exact-file adoption, customized QML preservation")
