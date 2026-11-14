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

    manager_path = home / ".local/share/awtarchy/awtarchy-compositor-manager.sh"
    assert manager_path in desired
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

    # The old installed menu source is registered only by its exact known Git
    # stock blob ID. A customized one must always be preserved.
    legacy_manager = b"#!/usr/bin/env bash\n# old stock Sway manager\n"
    current_baseline = json.loads(manifest.read_text())
    manager_key = str(manager_path.relative_to(home))
    current_baseline.pop(manager_key, None)
    manifest.write_text(json.dumps(current_baseline, indent=2) + "\n")
    manager_path.write_bytes(legacy_manager)
    with patch.object(sway_sync, "LEGACY_MANAGER_GIT_BLOBS",
                      frozenset({sway_sync.git_blob_sha1(legacy_manager)})):
        assert "recognized original trial manager" in run("review")
        assert "recognized original trial manager" in run("apply")
    assert manager_path.read_bytes() == desired[manager_path]
    assert any(path.read_bytes() == legacy_manager
               for path in manager_path.parent.glob(
                   "awtarchy-compositor-manager.sh.backup-*"))
    assert json.loads(manifest.read_text())[manager_key] == digest(
        desired[manager_path])

    custom = b"#!/usr/bin/env bash\n# user customization\n"
    current_baseline = json.loads(manifest.read_text())
    current_baseline.pop(manager_key)
    manifest.write_text(json.dumps(current_baseline, indent=2) + "\n")
    manager_path.write_bytes(custom)
    report = run("apply")
    assert "PRESERVE modified file: " + manager_key in report
    assert manager_path.read_bytes() == custom


# Hot activation must target exactly this Awtarchy Sway session. Mock the
# compositor and Quickshell commands; do not touch any real running session.
from types import SimpleNamespace

with tempfile.TemporaryDirectory(prefix="sway-live-reload-test-") as tmp:
    home = Path(tmp)
    manager = home / ".config/sway/awtarchy-trial/quickshell.sh"
    manager.parent.mkdir(parents=True)
    manager.write_bytes(b"#!/bin/bash\n")
    expected = {manager: manager.read_bytes()}
    config_key = ".config/sway/awtarchy-trial/config"
    shell_key = ".config/quickshell/awtarchy-sway/Bar.qml"
    active = dict(os.environ, XDG_CURRENT_DESKTOP="sway", SWAYSOCK="/tmp/sway.sock",
                  WAYLAND_DISPLAY="wayland-1")

    def response(argv, **kwargs):
        if argv[:3] == ["swaymsg", "-r", "-t"]:
            if argv[3] == "get_version":
                return SimpleNamespace(returncode=0, stdout=json.dumps({
                    "loaded_config_file_name": str(home / config_key)
                }), stderr="")
            if argv[3] == "command":
                assert argv[4] == "reload", argv
                return SimpleNamespace(returncode=0, stdout='[{"success":true}]', stderr="")
        if argv == ["bash", str(manager), "restart"]:
            assert kwargs["env"]["QUICKSHELL_CONFIG_NAME"] == "awtarchy-sway"
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError("Unexpected activation command: " + str(argv))

    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=response) as proc:
        sway_sync.activate_in_running_sway(home, expected, {config_key, shell_key})
        assert proc.call_count == 3
        assert proc.call_args_list[1].args[0][-1] == "reload"

    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=response) as proc:
        sway_sync.activate_in_running_sway(home, expected, {config_key})
        assert proc.call_count == 2  # no unnecessary shell restart

    def other_session(argv, **kwargs):
        assert argv[-1] == "get_version", argv
        return SimpleNamespace(returncode=0, stdout=json.dumps({
            "loaded_config_file_name": str(home / ".config/sway/config")
        }), stderr="")
    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=other_session) as proc:
        sway_sync.activate_in_running_sway(home, expected, {config_key, shell_key})
        assert proc.call_count == 1  # foreign Sway compositor untouched

    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Hyprland"}), \
         patch.object(sway_sync.subprocess, "run") as proc:
        sway_sync.activate_in_running_sway(home, expected, {config_key, shell_key})
        proc.assert_not_called()

    # If a managed manager is user-modified, do not execute or terminate it.
    manager.write_bytes(b"#!/bin/bash\n# user customized\n")
    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=response) as proc:
        sway_sync.activate_in_running_sway(home, expected, {shell_key})
        assert proc.call_count == 1

    # Sway session.sh update reimports the Qt6 theme and restarts only QS.
    session_key = ".config/sway/awtarchy-trial/session.sh"
    manager.write_bytes(expected[manager])
    def qt_response(argv, **kwargs):
        if argv[-1] == "get_version":
            return response(argv, **kwargs)
        if argv[:2] == ["dbus-update-activation-environment", "--systemd"]:
            assert kwargs["env"]["QT_QPA_PLATFORMTHEME"] == "qt5ct:qt6ct"
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if argv[:3] == ["systemctl", "--user", "import-environment"]:
            assert kwargs["env"]["QT_QPA_PLATFORMTHEME"] == "qt5ct:qt6ct"
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if argv == ["bash", str(manager), "restart"]:
            assert kwargs["env"]["QT_QPA_PLATFORMTHEME"] == "qt5ct:qt6ct"
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError("Unexpected Sway Qt activation: " + str(argv))
    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=qt_response) as qt:
        sway_sync.activate_in_running_sway(home, expected, {session_key})
        assert qt.call_count == 4

    # A failed reload is reported after writes, never disguised as success.
    manager.write_bytes(expected[manager])
    def rejected(argv, **kwargs):
        if argv[-1] == "get_version":
            return response(argv, **kwargs)
        return SimpleNamespace(returncode=2, stdout='[{"success":false}]', stderr="invalid")
    with patch.dict(os.environ, active), patch.object(sway_sync.subprocess, "run",
                                                     side_effect=rejected):
        try:
            sway_sync.activate_in_running_sway(home, expected, {config_key, shell_key})
        except ValueError as exc:
            assert "reload failed" in str(exc), exc
        else:
            raise AssertionError("Rejected live reload must not report success")


# A picker configuration update must refresh only idle xdpw backends, never
# kill active recording streams. No portal restart for a missing PipeWire probe.
from types import SimpleNamespace as Result

def portal_response(argv, **kwargs):
    if argv[:3] == ["systemctl", "--user", "is-active"]:
        return Result(returncode=0, stdout="", stderr="")
    if argv == ["pw-dump"]:
        return Result(returncode=0, stdout=json.dumps([]), stderr="")
    if argv[:3] == ["systemctl", "--user", "restart"]:
        return Result(returncode=0, stdout="", stderr="")
    raise AssertionError("Unexpected portal command: " + str(argv))

with patch.object(sway_sync.subprocess, "run", side_effect=portal_response) as run_portal:
    sway_sync.refresh_sway_portal_if_safe()
    assert run_portal.call_count == 3
    assert run_portal.call_args_list[-1].args[0] == [
        "systemctl", "--user", "restart", "xdg-desktop-portal-wlr.service"]

def portal_streaming(argv, **kwargs):
    if argv[:3] == ["systemctl", "--user", "is-active"]:
        return Result(returncode=0, stdout="", stderr="")
    if argv == ["pw-dump"]:
        return Result(returncode=0, stdout=json.dumps([
            {"type":"PipeWire:Interface:Node",
             "info":{"props":{"node.name":"xdpw-stream-abcdef"}}}]), stderr="")
    raise AssertionError("An active stream must never be restarted")

with patch.object(sway_sync.subprocess, "run", side_effect=portal_streaming) as run_portal:
    sway_sync.refresh_sway_portal_if_safe()
    assert run_portal.call_count == 2

def portal_unknown(argv, **kwargs):
    if argv[:3] == ["systemctl", "--user", "is-active"]:
        return Result(returncode=0, stdout="", stderr="")
    if argv == ["pw-dump"]:
        return Result(returncode=1, stdout="", stderr="missing")
    raise AssertionError("Unknown streaming status must never restart portal")

with patch.object(sway_sync.subprocess, "run", side_effect=portal_unknown) as run_portal:
    sway_sync.refresh_sway_portal_if_safe()
    assert run_portal.call_count == 2

print("PASS: live Sway session reload, shell-only restart and foreign-session protection")

print("PASS: missing generated Sway QML install, exact-file adoption, customized QML preservation")
