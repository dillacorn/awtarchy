#!/usr/bin/env python3
"""Isolated, read-only tests for Umbriel registration in Ly's custom list."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "trials/umbriel/register-ly-session.sh"
source = SCRIPT.read_text(encoding="utf-8")
assert 'sudo ln -sT -- "$source" "$target"' in source
assert 'Name=Umbriel' in source
assert 'owner' in source and 'umbriel-git' in source
assert 'PRESERVE: destination already exists' in source
assert 'waylandsessions' in source
assert '/etc/ly/awtarchy-wayland-sessions' in source
subprocess.run(["bash", "-n", str(SCRIPT)], check=True)

with tempfile.TemporaryDirectory(prefix="awtarchy-umbriel-ly-") as temp:
    root = Path(temp)
    configdir = root / "etc/ly"
    custom = configdir / "awtarchy-wayland-sessions"
    native = root / "usr/share/wayland-sessions"
    bin_dir = root / "bin"
    configdir.mkdir(parents=True)
    native.mkdir(parents=True)
    bin_dir.mkdir()
    entry = native / "umbriel.desktop"
    entry.write_text(
        "[Desktop Entry]\nName=Umbriel\nExec=start-umbriel\n"
        "Type=Application\nDesktopNames=Umbriel\n",
        encoding="utf-8")
    config = configdir / "config.ini"
    config.write_text(
        "[general]\nwaylandsessions = " + str(custom) + "\n",
        encoding="utf-8")
    launcher = bin_dir / "start-umbriel"
    launcher.write_text("#!/bin/sh\nprintf ready\n")
    launcher.chmod(0o755)
    pacman = bin_dir / "pacman"
    pacman.write_text(
        "#!/bin/sh\n"
        'if [ "$1" = "-Qqo" ]; then printf "umbriel-git\\n"; '
        "else return 1 2>/dev/null || false; fi\n")
    pacman.chmod(0o755)

    rendered = source
    for old, new in (
        ("source=/usr/share/wayland-sessions/umbriel.desktop", "source=" + str(entry)),
        ("config=/etc/ly/config.ini", "config=" + str(config)),
        ("native=/usr/share/wayland-sessions", "native=" + str(native)),
        ("custom=/etc/ly/awtarchy-wayland-sessions", "custom=" + str(custom)),
        ('[[ -d /etc/ly && ! -L /etc/ly', '[[ -d "' + str(configdir) +
         '" && ! -L "' + str(configdir) + '"'),
        ('"$(stat -c %u -- /etc/ly)" == 0',
         '"$(stat -c %u -- "' + str(configdir) + '")" == ' + str(os.getuid())),
        ('"$(stat -c %u -- "$custom")" == 0',
         '"$(stat -c %u -- "$custom")" == ' + str(os.getuid())),
        ('[[ "$(id -u)" -ne 0 ]]',
         '[[ "$(id -u)" -ge 0 ]]'),
    ):
        if rendered.count(old) != 1:
            raise AssertionError("Unsafe fixture substitution: " + old)
        rendered = rendered.replace(old, new)
    fixture = root / "register-test.sh"
    fixture.write_text(rendered, encoding="utf-8")
    fixture.chmod(0o700)
    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
    target = custom / "umbriel.desktop"

    def run():
        return subprocess.run(["bash", str(fixture), "plan"], env=env,
                              text=True, capture_output=True, timeout=15)

    # No silent creation of a private Ly directory.
    missing = run()
    assert missing.returncode != 0 and not custom.exists(), missing
    custom.mkdir()

    planned = run()
    assert planned.returncode == 0 and "WOULD LINK:" in planned.stdout, planned
    assert not target.exists(), "Preview changed Ly session directory"

    # Existing unmanaged session (even with another filename) must not
    # create a second Umbriel entry.
    alternate = custom / "other-umbriel.desktop"
    alternate.write_text("[Desktop Entry]\nName=Umbriel\nExec=start-umbriel\n")
    conflict = run()
    assert conflict.returncode != 0 and "PRESERVE" in conflict.stderr, conflict
    alternate.unlink()

    target.write_text("[Desktop Entry]\nName=My custom Umbriel\n")
    conflict = run()
    assert conflict.returncode != 0 and "PRESERVE" in conflict.stderr, conflict
    assert target.is_file()
    target.unlink()

    # An exact preexisting link is idempotent, including in apply mode:
    # it terminates safely before reaching an interactive prompt or sudo.
    target.symlink_to(entry)
    same = subprocess.run(["bash", str(fixture), "apply"], env=env,
                          text=True, capture_output=True, timeout=15)
    assert same.returncode == 0 and "already has" in same.stdout, same
    assert target.is_symlink() and target.resolve() == entry
    target.unlink()

    # When Ly already scans the native package directory, never add a
    # redundant Umbriel entry in the custom list.
    config.write_text("[general]\nwaylandsessions = " + str(native) + "\n")
    native_path = run()
    assert native_path.returncode == 0 and "no extra" in native_path.stdout
    assert not target.exists()

    # A surprising custom path is not silently rewritten.
    config.write_text("[general]\nwaylandsessions = /unrelated/sessions\n")
    surprising = run()
    assert surprising.returncode != 0 and "Preserving" in surprising.stderr
    assert not target.exists()

print("PASS: Ly Umbriel registration plans one link, preserves custom entries and rejects unsafe paths")
