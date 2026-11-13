#!/usr/bin/env python3
"""Prevent Sway update regressions that omit newly required generated QML.

This stages a complete, isolated fake home and real renderer output. It does
not modify the developer's actual Sway, Hyprland, or Quickshell files.
"""
import hashlib
import io
import json
import os
from contextlib import redirect_stdout
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

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

    def run(mode):
        output = io.StringIO()
        # CI runs its Arch container as root. The real updater must reject
        # root, so emulate only the current uid while exercising its real
        # main() implementation against an isolated temporary home.
        with patch.dict(os.environ, {"HOME": str(home)}), \
             patch.object(sway_sync.os, "geteuid", return_value=1000), \
             patch.object(sys, "argv", [str(SYNC), mode, "--repo", str(ROOT)]), \
             redirect_stdout(output):
            sway_sync.main()
        return output.getvalue()

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

    # Reproduce the user's manual recovery: an old QML component exists, but
    # the baseline never recorded it. Only recognized stock bytes may upgrade.
    legacy = b"// original hand-installed Sway layer-shell QML\n"
    installed = json.loads(manifest.read_text())
    installed.pop(key)
    manifest.write_text(json.dumps(installed, indent=2) + "\n")
    missing.write_bytes(legacy)
    original_hashes = sway_sync.LEGACY_MANUAL_INSTALL_HASHES
    with patch.object(sway_sync, "LEGACY_MANUAL_INSTALL_HASHES",
                      {key: frozenset({digest(legacy)})}):
        assert "recognized old manual Sway hotfix" in run("review")
        assert "recognized old manual Sway hotfix" in run("apply")
    assert missing.read_bytes() == desired[missing]
    assert any(
        path.read_bytes() == legacy
        for path in missing.parent.glob("SwayFlyoutWindow.qml.backup-*")
    ), "Manually installed stock QML must be backed up before replacement"
    assert json.loads(manifest.read_text())[key] == digest(desired[missing])
    assert key in original_hashes
    assert len(next(iter(original_hashes[key]))) == 64

    # If the user edits their managed QML, the updater must never overwrite.
    missing.write_bytes(b"// personal Sway QML modification\n")
    report = run("apply")
    assert "PRESERVE modified file: " + key in report, report
    assert missing.read_bytes() == b"// personal Sway QML modification\n"

print("PASS: missing generated Sway QML install, exact-file adoption, customized QML preservation")
