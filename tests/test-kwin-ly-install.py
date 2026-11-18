#!/usr/bin/env python3
"""Simulate privileged Ly registration without touching real system paths."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1] / "trials/kwin"

with tempfile.TemporaryDirectory(prefix="kwin-ly-fixture-") as temporary:
    base = Path(temporary)
    source = base / "source"
    source.mkdir()
    bin_path = base / "bin"
    bin_path.mkdir()
    local_bin = base / "local-bin"
    local_bin.mkdir()
    sessions = base / "wayland-sessions"
    sessions.mkdir()
    home = base / "home"
    trial = home / ".local/share/awtarchy-kwin-trial"
    trial.mkdir(parents=True)
    (trial / "tty-smoke.sh").write_text("# harmless fixture\n")
    wrapper = local_bin / "awtarchy-kwin-trial-session"
    entry = sessions / "awtarchy-kwin-trial.desktop"
    shutil.copy(ROOT / "ly-session.sh", source / "ly-session.sh")
    desktop = (ROOT / "kwin.desktop").read_text()
    (source / "kwin.desktop").write_text(desktop.replace(
        "/usr/local/bin/awtarchy-kwin-trial-session", str(wrapper)))

    setup = (ROOT / "setup-ly.sh").read_text()
    setup = setup.replace("/usr/local/bin", str(local_bin))
    setup = setup.replace("/usr/share/wayland-sessions", str(sessions))
    setup = setup.replace("/usr/bin/kwin_wayland", str(bin_path / "kwin_wayland"))
    setup = setup.replace("/usr/bin/qs", str(bin_path / "qs"))
    setup = setup.replace("/usr/bin/foot", str(bin_path / "foot"))
    setup = setup.replace("/usr/bin/fuzzel", str(bin_path / "fuzzel"))
    setup = setup.replace(
        "/usr/bin/python3 -c 'import dbus_next'",
        "/usr/bin/python3 -c 'pass'")
    # CI can run unprivileged; mock only the fixture's owner assertion,
    # never the real installed shell script.
    setup = setup.replace(
        '"$(stat -c %u -- "$dest")" == 0',
        '"$(stat -c %u -- "$dest")" == "$(id -u)"')
    if os.geteuid() == 0:
        setup = setup.replace('[[ ${EUID} -ne 0 ]]',
                              '[[ 1000 -ne 0 ]]')
    (source / "setup-ly.sh").write_text(setup)

    for name in ("kwin_wayland", "qs", "foot", "fuzzel"):
        path = bin_path / name
        path.write_text("#!/usr/bin/env bash\ntrue\n")
        path.chmod(0o755)
    sudo = bin_path / "sudo"
    sudo.write_text("#!/usr/bin/env bash\n\"$@\"\n")
    sudo.chmod(0o755)
    pacman = bin_path / "pacman"
    pacman.write_text("#!/usr/bin/env bash\nreturn 1 2>/dev/null || false\n")
    pacman.chmod(0o755)
    env = dict(os.environ)
    env.update({
        "HOME": str(home),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "PATH": f"{bin_path}:{os.environ['PATH']}",
    })

    def run(action: str, ok: bool = True):
        result = subprocess.run(
            ["bash", str(source / "setup-ly.sh"), action],
            env=env, text=True, capture_output=True, timeout=15)
        assert (result.returncode == 0) == ok, (
            action, result.returncode, result.stdout, result.stderr)
        return result

    run("plan")
    assert not wrapper.exists() and not entry.exists()
    run("apply")
    assert wrapper.is_file() and entry.is_file()
    assert "Name=KWin (Awtarchy Trial)" in entry.read_text()
    assert str(wrapper) in entry.read_text()
    run("apply")
    entry.write_text("custom user session\n")
    run("remove", ok=False)
    assert entry.read_text() == "custom user session\n"
    assert wrapper.exists()
    entry.write_bytes((source / "kwin.desktop").read_bytes())
    run("remove")
    assert not wrapper.exists() and not entry.exists()

print("PASS: KWin Ly plan/apply/remove, no-overwrite and safe collision handling")
