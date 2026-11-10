#!/usr/bin/env python3
"""Prove compositor menu preview never installs/removes, and branch is explicit."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = root / "local/share/awtarchy/awtarchy-compositor-manager.sh"
launcher = (root / "local/bin/awtarchy").read_text()
installer = (root / "awtarchy-install.sh").read_text()
runtime = (root / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
subprocess.run(["bash", "-n", str(manager)], check=True)
assert "compositor_menu()" in launcher
assert '"Manage compositors (Hyprland / Jay)"' in launcher
assert "compositor_offer_once" in launcher
assert "compositor_trial_installed" in launcher
assert "install_trial_compositor_command" in installer
assert "compositor-trial-source" in installer and "compositor-trial-source" in runtime
assert "aur-scan install jay --noconfirm" in manager.read_text()
assert "pacman -R --noconfirm" in manager.read_text()
assert "pacman -Rns" not in manager.read_text()
assert "Cannot remove the last" in manager.read_text()
assert "Cannot remove" in manager.read_text()
with tempfile.TemporaryDirectory(prefix="awtarchy-compositor-test.") as folder:
    temp = Path(folder)
    bin_dir = temp / "bin"
    bin_dir.mkdir()
    log = temp / "calls.log"
    fake = bin_dir / "pacman"
    fake.write_text(
        '#!/usr/bin/env bash\n'
        'if [[ "$1" == "-Qq" ]]; then\n'
        '  if [[ "$2" == hyprland ]]; then return 0; fi\n'
        '  return 1\n'
        'fi\n'
        f'printf "WRITTEN %s\\\\n" "$*" >> "{log}"\n'
        'return 77\n')
    fake.chmod(0o755)
    for name in ("sudo", "aur-scan"):
        target = bin_dir / name
        target.write_text(f'#!/usr/bin/env bash\nprintf "CALLED {name}\\\\n" >> "{log}"\nreturn 88\n')
        target.chmod(0o755)
    home = temp / "home"
    state = home / ".local/state/awtarchy"
    state.mkdir(parents=True)
    (state / "compositor-trial-source").write_text(str(root) + "\n")
    env = dict(os.environ, HOME=str(home), PATH=str(bin_dir) + ":" + os.environ.get("PATH", ""),
               XDG_CURRENT_DESKTOP="Hyprland")
    for action in ("status", "install-jay", "install-hyprland",
                   "remove-jay", "remove-hyprland"):
        result = subprocess.run(["bash", str(manager), action, "plan", "yes"],
                                env=env, capture_output=True, text=True, timeout=7)
        assert result.returncode == 0, (action, result.stderr)
        if action != "status":
            assert "Preview only" in result.stdout
        assert not log.exists(), (action, "write attempted in plan mode")
    attempt = subprocess.run(["bash", str(manager), "remove-jay", "apply", "yes"],
                             env=env, capture_output=True, text=True, timeout=7)
    assert attempt.returncode != 0
    assert not log.exists(), "Noninteractive apply invoked package manager"
    (state / "compositor-trial-source").unlink()
    blocked = subprocess.run(["bash", str(manager), "install-jay", "plan", "no"],
                             env=env, capture_output=True, text=True, timeout=7)
    assert blocked.returncode != 0
print("PASS: compositor menus/ownership safeguards and read-only previews")
