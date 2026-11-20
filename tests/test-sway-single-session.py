#!/usr/bin/env python3
"""Single native Sway Ly entry and non-destructive legacy migration."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
SCRIPT = TRIAL / "legacy-session-cleanup.sh"
MANAGER = (ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh").read_text()
RUNTIME = (ROOT / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
LAUNCHER = (ROOT / "local/bin/awtarchy").read_text()
SETUP = (TRIAL / "setup.sh").read_text()
ENTRY = (TRIAL / "native-config").read_text()
assert ENTRY.strip().endswith("include awtarchy-trial/config")
assert 'native_config="$config/sway/config"' in SETUP
assert 'install -m 0644 -- "$native_source" "$native_config"' in SETUP
assert 'legacy-session-cleanup.sh" apply "$repo"' in MANAGER
assert 'legacy-session-cleanup.sh" apply "$REPO_DIR"' in RUNTIME
assert '"$repo/trials/sway/sway.desktop:$session_file"' not in MANAGER
assert 'install -m 0644 -- "${source}/sway.desktop" "$desktop"' not in RUNTIME
assert "AWTARCHY_COMPOSITOR_MENU_APPROVED" in MANAGER
for script in (SCRIPT, TRIAL / "setup.sh",
               ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh",
               ROOT / "local/bin/awtarchy"):
    subprocess.run(["bash", "-n", str(script)], check=True)
menu = LAUNCHER.split("compositor_menu() {", 1)[1].split(
    "\ncompositor_offer_once() {", 1)[0]
assert "Preview: add Sway" not in menu
assert "preserve Hyprland)" not in menu
assert 'options+=("Install Sway")' in menu
assert 'options+=("Update Sway")' in menu
assert 'options+=("Remove Hyprland" "Remove Sway")' in menu
assert 'options+=("Back")' in menu
assert 'single_select_menu "$title" 0 "$action" "Cancel"' in menu

with tempfile.TemporaryDirectory(prefix="sway-native-ly-test-") as tmp:
    root = Path(tmp)
    native = root / "sway.desktop"
    legacy = root / "awtarchy-sway-trial.desktop"
    source = TRIAL / "sway.desktop"
    native.write_text("[Desktop Entry]\nName=Sway\nExec=sway\n")
    fakebin = root / "bin"
    fakebin.mkdir()
    (fakebin / "pacman").write_text("#!/bin/sh\nreturn 1 2>/dev/null || false\n")
    (fakebin / "sudo").write_text('#!/bin/sh\n"$@"\n')
    for file in fakebin.iterdir():
        file.chmod(0o755)
    fixture = root / "cleanup"
    shell = SCRIPT.read_text().replace(
        "legacy=/usr/share/wayland-sessions/awtarchy-sway-trial.desktop",
        "legacy=" + str(legacy)
    ).replace(
        "native=/usr/share/wayland-sessions/sway.desktop",
        "native=" + str(native)
    )
    fixture.write_text(shell)
    fixture.chmod(0o755)
    env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"])

    def run(mode):
        return subprocess.run(["bash", str(fixture), mode, str(ROOT)],
                              env=env, capture_output=True, text=True, timeout=10)

    assert run("apply").returncode == 0, "No duplicate should be a no-op"
    legacy.write_bytes(source.read_bytes())
    before = legacy.read_bytes()
    preview = run("plan")
    assert preview.returncode == 0 and "WOULD REMOVE" in preview.stdout
    assert legacy.read_bytes() == before, "Preview modified the duplicate"
    done = run("apply")
    assert done.returncode == 0, (done.stdout, done.stderr)
    assert not legacy.exists() and native.exists()
    legacy.write_text("[Desktop Entry]\nName=Custom Sway\nExec=sway\n")
    custom = run("apply")
    assert custom.returncode != 0 and "PRESERVE" in custom.stderr
    assert legacy.read_text().startswith("[Desktop Entry]\nName=Custom")
    legacy.unlink()
    legacy.symlink_to(native)
    assert run("apply").returncode != 0 and legacy.is_symlink()
    legacy.unlink()
    native.unlink()
    assert run("plan").returncode != 0, "Missing native session should fail"

print("PASS: one native Sway entry, exact obsolete entry cleanup and custom preservation")
