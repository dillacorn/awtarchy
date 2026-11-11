#!/usr/bin/env python3
"""Run Sway's screenshot helper against isolated command mocks (no display)."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "trials/sway/capture.sh"

with tempfile.TemporaryDirectory(prefix="sway-satty-contract-") as directory:
    root = Path(directory)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    (root / "run").mkdir()
    (root / "home").mkdir()
    events = root / "events"

    mocks = {
        "grim": r"""#!/usr/bin/env bash
set -euo pipefail
printf 'grim:%s\n' "$*" >>"$EVENTS"
[[ "$1" == "-g" ]] || exit 2
printf 'fakePNG' > "$3"
""",
        "slurp": r"""#!/usr/bin/env bash
set -euo pipefail
printf 'slurp:%s\n' "$*" >>"$EVENTS"
printf '10,20 300x200\n'
""",
        "wl-copy": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--type" && "$2" == "image/png" ]] || exit 2
[[ "$(cat)" == "fakePNG" ]] || exit 3
printf 'clipboard\n' >>"$EVENTS"
[[ ! -e /proc/self/fd/9 ]] || exit 14
# Emulate wl-copy keeping a clipboard-serving process alive after return.
sleep 2 >/dev/null 2>&1 &
""",
        "satty": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--filename" && -s "$2" ]] || exit 2
[[ "$3" == "--output-filename" && "$4" == "$HOME/Pictures/Screenshots/"* ]] || exit 3
[[ "$5" == "--default-hide-toolbars" ]] || exit 4
printf 'satty:%s\n' "$2" >>"$EVENTS"
""",
        "swaymsg": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "-r" && "$2" == "-t" && "$3" == get_tree ]] || exit 2
printf '%s\n' '{"type":"root","nodes":[{"type":"workspace","nodes":[{"type":"con","id":3,"name":"Example","app_id":"example","visible":true,"rect":{"x":10,"y":20,"width":300,"height":200}}]}]}'
""",
    }
    for name, code in mocks.items():
        path = bin_dir / name
        path.write_text(code)
        path.chmod(0o755)
    env = os.environ.copy()
    env.update({
        "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
        "XDG_CURRENT_DESKTOP": "sway",
        "WAYLAND_DISPLAY": "wayland-test",
        "SWAYSOCK": "/tmp/test-sway.sock",
        "XDG_RUNTIME_DIR": str(root / "run"),
        "HOME": str(root / "home"),
        "EVENTS": str(events),
    })
    for mode in ("area", "window", "display", "output"):
        events.write_text("")
        result = subprocess.run(
            ["bash", str(SCRIPT), mode], env=env,
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (mode, result.stdout, result.stderr)
        lines = events.read_text().splitlines()
        assert lines[0].startswith("slurp:"), (mode, lines)
        assert lines[1].startswith("grim:"), (mode, lines)
        assert lines[2] == "clipboard", (mode, lines)
        assert lines[3].startswith("satty:"), (mode, lines)
        assert not Path(lines[3].split("satty:", 1)[1]).exists(), mode
        if mode == "window":
            assert "-r" in lines[0]
        if mode in ("display", "output"):
            assert "-o" in lines[0]

    # A second screenshot must succeed while the previous clipboard provider
    # remains running; the old inherited flock caused a false lock-busy.
    events.write_text("")
    retry = subprocess.run(
        ["bash", str(SCRIPT), "area"], env=env,
        capture_output=True, text=True, timeout=10
    )
    assert retry.returncode == 0, (retry.stdout, retry.stderr)
    assert any(x.startswith("satty:") for x in events.read_text().splitlines())

    env["XDG_CURRENT_DESKTOP"] = "Hyprland"
    events.write_text("")
    denied = subprocess.run(["bash", str(SCRIPT), "area"], env=env,
                            capture_output=True, text=True, timeout=5)
    assert denied.returncode != 0
    assert not events.read_text()

print("PASS: Sway capture displays Satty after clipboard copy, unlocks capture and refuses Hyprland")
