#!/usr/bin/env python3
"""Offline Umbriel installation, Quickshell bridge, and preservation contracts."""
from __future__ import annotations
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "compositors/umbriel"
for script in (TRIAL / "session.sh", TRIAL / "ipc.sh",
               TRIAL / "manage.sh", TRIAL / "position.sh",
               TRIAL / "runtime-rules.sh", TRIAL / "diagnose-session.sh",
               ROOT / "local/bin/awtarchy"):
    subprocess.run(["bash", "-n", str(script)], check=True)
config = tomllib.loads((TRIAL / "config.toml").read_text())
assert config["layout"]["mode"] == "dwindle"
assert config["general"]["autostart"] == [
    "bash ~/.config/umbriel/awtarchy-trial/session.sh"]
assert "tearing" not in (TRIAL / "config.toml").read_text().split(
    "[general]", 1)[1].split("[layout]", 1)[0]
assert "umbriel-git" in (TRIAL / "manage.sh").read_text()
assert "yay -S --needed umbriel-git" in (TRIAL / "manage.sh").read_text()
assert "/usr/share/wayland-sessions/umbriel.desktop" in (TRIAL / "manage.sh").read_text()
assert "Ly visibility is not yet verified" in (TRIAL / "manage.sh").read_text()
diagnostic = (TRIAL / "diagnose-session.sh").read_text()
assert "systemctl show ly.service --no-pager" in diagnostic
assert "pacman -Qo --" in diagnostic
assert "waylandsessions" in diagnostic
assert "awtarchy-umbriel" in (TRIAL / "render-quickshell.py").read_text()
assert '"Install Umbriel"' in (ROOT / "local/bin/awtarchy").read_text()
launcher = (ROOT / "local/bin/awtarchy").read_text()
runtime = (ROOT / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
menu = launcher.split("compositor_menu() {", 1)[1].split(
    "\ncompositor_offer_once() {", 1)[0]
assert 'remove-umbriel' in (TRIAL / "manage.sh").read_text()
assert 'pacman -R --print --print-format' in (TRIAL / "manage.sh").read_text()
assert 'sudo pacman -R --noconfirm -- "$target"' in (TRIAL / "manage.sh").read_text()
assert 'Cannot remove the last supported compositor' in (TRIAL / "manage.sh").read_text()
assert 'Type %s to authorize' not in (TRIAL / "manage.sh").read_text()
assert 'Type %s to authorize installation' not in (TRIAL / "manage.sh").read_text()
assert 'AWTARCHY_COMPOSITOR_MENU_APPROVED' not in (TRIAL / "manage.sh").read_text()
assert '"Cancel"' in menu and 'single_select_menu "$title" 0 "$action" "Cancel"' in menu
assert '"Update Umbriel"' not in menu
assert '"Update Sway"' not in menu
assert '"Remove Umbriel"' in menu
assert '"Remove Hyprland" "Remove Sway"' in menu
assert '"Install Umbriel"' in menu
assert '"Update configs (preserve personal customizations)"' in launcher
review = runtime.split('if (( REVIEW_ONLY == 1 )); then', 1)[1].split(
    'log "Review-only mode complete.', 1)[0]
assert 'compositors/sway/sync.py" review' in review
assert 'compositors/sway/session-wrapper-update.sh" plan' in review
assert 'compositors/sway/legacy-session-cleanup.sh" plan' in review
assert 'compositors/umbriel/sync.py" preview' in review
accepted = runtime.split('if ! confirm_live_update_result; then', 1)[1]
assert 'compositors/sway/sync.py" apply' in accepted
assert 'compositors/sway/session-wrapper-update.sh" apply' in accepted
assert 'compositors/sway/legacy-session-cleanup.sh" apply' in accepted
assert 'compositors/umbriel/sync.py" apply' in accepted
assert 'umbriel-trial-baseline.json' in accepted
assert accepted.index('compositors/umbriel/sync.py" apply') < accepted.index(
    'log "Reconciling hardware and managed packages..."')
assert 'AWTARCHY_UMBRIEL_TRIAL_SOURCE' in launcher
assert 'AWTARCHY_COMPOSITOR_RELEASE_SOURCE="$umbriel_repo"' in launcher
assert 'bash "$umbriel_repo/local/share/awtarchy/awtarchy-compositor-manager.sh" "$@"' in launcher
assert 'status|install-sway|install-hyprland|remove-sway|remove-hyprland' in launcher
assert 'AWTARCHY_COMPOSITOR_MENU_APPROVED' not in launcher
core = (ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh").read_text()
assert "Type %s to authorize" not in core
assert "sudo pacman -R --noconfirm" in core
assert "Personal configs are preserved" in core

with tempfile.TemporaryDirectory(prefix="umbriel-trial-test-") as temp:
    root = Path(temp)
    rendered = root / "quickshell"
    subprocess.run([
        sys.executable, str(TRIAL / "render-quickshell.py"),
        "--repo", str(ROOT), "--dest", str(rendered)],
        capture_output=False, check=True, timeout=90)
    assert (rendered / "shell.qml").is_file()
    assert (rendered / "UmbrielBridge.qml").is_file()
    assert "native portal" in (rendered / "ScreenSharePicker.qml").read_text()
    assert "/sway/awtarchy-trial/" not in (rendered / "ScreenSharePicker.qml").read_text()
    assert (rendered / "UmbrielFlyoutWindow.qml").is_file()
    for source in rendered.glob("*.qml"):
        text = source.read_text()
        assert "import Quickshell.I3" not in text, source
        assert 'hyprctl ' not in text and 'swaymsg ' not in text, source
    assert "UmbrielBridge" in (rendered / "Bar.qml").read_text()
    assert "awtarchy-umbriel" in (rendered / "shell.qml").read_text()
    home = root / "home"
    home.mkdir()
    hypr = home / ".config/hypr/hyprland.lua"
    sway = home / ".config/sway/awtarchy-trial/config"
    mango = home / ".local/state/awtarchy/config-version"
    for path, value in ((hypr, "original hyprland"),
                        (sway, "original sway"),
                        (mango, "MangoWM_Migration_Trial_Investigation")):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    spec = importlib.util.spec_from_file_location("umbriel_sync", TRIAL / "sync.py")
    sync = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sync)
    # We cannot test a real AUR build or GPU here. This is only file staging.
    if os.geteuid() == 0:
        patch_user = patch.object(sync.os, "geteuid", return_value=1000)
    else:
        from contextlib import nullcontext
        patch_user = nullcontext()
    with patch_user:
        sync.reconcile(ROOT, home, "preview")
        assert not (home / ".config/umbriel").exists()
        sync.reconcile(ROOT, home, "apply")
        assert (home / ".config/umbriel/config.toml").exists()
        assert (home / ".config/quickshell/awtarchy-umbriel/shell.qml").exists()
        personal = home / ".config/quickshell/awtarchy-umbriel/Bar.qml"
        personal.write_text("personal Umbriel bar; do not overwrite")
        sync.reconcile(ROOT, home, "apply")
        assert personal.read_text() == "personal Umbriel bar; do not overwrite"
        native = home / ".config/umbriel/config.toml"
        assert native.read_bytes() == (TRIAL / "native-config.toml").read_bytes()
        for path, value in ((hypr, "original hyprland"),
                            (sway, "original sway"),
                            (mango, "MangoWM_Migration_Trial_Investigation")):
            assert path.read_text() == value
        # Simulate an updated immutable release: preview must be read-only,
        # apply must back up the exact old managed file, and a customized
        # Quickshell component must remain untouched.
        session = home / ".config/umbriel/awtarchy-trial/session.sh"
        original_session = session.read_bytes()
        desired_original = sync.desired_files

        def newer_release(repo, target_home, stage):
            desired = desired_original(repo, target_home, stage)
            desired[session] = desired[session] + b"\n# managed update test\n"
            return desired

        with patch.object(sync, "desired_files", side_effect=newer_release):
            sync.reconcile(ROOT, home, "preview")
            assert session.read_bytes() == original_session
            sync.reconcile(ROOT, home, "apply")
        assert session.read_bytes() == original_session + b"\n# managed update test\n"
        backups = list(session.parent.glob("session.sh.backup-*"))
        assert len(backups) == 1 and backups[0].read_bytes() == original_session
        assert personal.read_text() == "personal Umbriel bar; do not overwrite"

        native.write_text("# personal Umbriel setup")
        try:
            sync.reconcile(ROOT, home, "preview")
        except ValueError:
            pass
        else:
            raise AssertionError("Would silently adopt a custom native Umbriel config")

    # Verify the JSON adapters against documented upstream command fields.
    fakebin = root / "bin"
    fakebin.mkdir()
    binary = fakebin / "umbriel"
    fixtures = {
        "outputs": [{"name": "DP-3", "enabled": True, "focused": True,
                     "position": {"x": 0, "y": 0}, "scale": 1.0,
                     "logical_size": {"width": 1920, "height": 1080},
                     "modes": [{"width": 1920, "height": 1080,
                                "refresh_mhz": 240000, "current": True}]}],
        "workspaces": [{"id": "ws1", "name": "1", "index": 1, "output": "DP-3",
                        "active": True, "focused": True, "urgent": False}],
        "windows": [{"id": "window1", "workspace": "ws1", "output": "DP-3",
                     "app_id": "foot", "title": "Terminal", "active": True,
                     "urgent": False, "fullscreen": False}]
    }
    binary.write_text("#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "data=json.loads(Path(os.environ['UMB_FIXTURES']).read_text())\n"
        "print(json.dumps(data[sys.argv[1]]))\n")
    binary.chmod(0o755)
    fixture = root / "fixtures.json"
    fixture.write_text(json.dumps(fixtures))
    env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
               UMB_FIXTURES=str(fixture))
    for script, arg in (("workspace-state.py", None),
                        ("monitor-info.py", "monitors"),
                        ("monitor-info.py", "activeworkspace")):
        command = [sys.executable, str(TRIAL / script)]
        if arg: command.append(arg)
        result = subprocess.run(command, env=env, check=True,
                                capture_output=True, text=True, timeout=10)
        payload = json.loads(result.stdout)
        if script == "workspace-state.py":
            assert payload[0]["clients"][0]["app_id"] == "foot"
        elif arg == "monitors":
            assert payload[0]["refresh_rate"] == 240
        else:
            assert payload["id"] == 1
print("PASS: Umbriel trial renderer, IPC adapters, config preservation and bash syntax")
