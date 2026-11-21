#!/usr/bin/env python3
"""Offline contracts for Steam's one-shot native Umbriel 80/20 split."""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "compositors/umbriel/steam-layout.sh"
LAUNCHER = ROOT / "config/hypr/scripts/steam_launcher.sh"
SYNC = ROOT / "compositors/umbriel/sync.py"

assert shutil.which("jq"), "jq is required for the actual Steam layout contract"
for script in (HELPER, LAUNCHER):
    subprocess.run(["bash", "-n", str(script)], check=True)

launcher_source = LAUNCHER.read_text()
assert 'case "${XDG_CURRENT_DESKTOP,,}" in' in launcher_source
assert 'hypr/scripts/splitratio_steam.sh' in launcher_source
assert 'umbriel/awtarchy/steam-layout.sh' in launcher_source
assert 'umbriel' in launcher_source and 'hyprland' in launcher_source
assert '"$splitratio" >/dev/null 2>&1 &' in launcher_source
assert '"steam-layout.sh"' in SYNC.read_text()

windows = [
    {
        "id": "2cb5819d9b057f9b0b661e378b3f3673",
        "app_id": "steam", "title": "Steam", "workspace": "DP-1:4",
        "output": "DP-1", "visible": True, "floating": False,
        "fullscreen": False, "x": 7, "w": 1010,
    },
    {
        "id": "3e67feedbb851d9b9b9849f23ba91390",
        "app_id": "steam", "title": "Friends List", "workspace": "DP-1:4",
        "output": "DP-1", "visible": True, "floating": False,
        "fullscreen": False, "x": 964, "w": 949,
    },
]

with tempfile.TemporaryDirectory(prefix="umbriel-steam-layout-") as tmp:
    base = Path(tmp)
    fakebin = base / "bin"
    fakebin.mkdir()
    binary = fakebin / "umbriel"
    binary.write_text(
        "#!/usr/bin/env python3\n"
        "import os, sys\n"
        "from pathlib import Path\n"
        "args = sys.argv[1:]\n"
        "if args == ['windows', '--json']:\n"
        "    print(Path(os.environ['MOCK_WINDOWS']).read_text())\n"
        "else:\n"
        "    with Path(os.environ['MOCK_LOG']).open('a') as log:\n"
        "        log.write(' '.join(args) + '\\n')\n"
        "    if os.environ.get('MOCK_FOCUS_FAIL') == '1' and args[:2] == ['msg', 'window-focus']:\n"
        "        raise SystemExit(2)\n"
    )
    binary.chmod(0o755)

    def run_case(label: str, payload: list[dict], *,
                 desktop: str = "Umbriel", focus_fail: bool = False,
                 expect_wait: bool = False) -> tuple[int, list[str]]:
        runtime = base / ("runtime-" + label)
        runtime.mkdir()
        data = base / (label + ".json")
        data.write_text(json.dumps(payload))
        log = base / (label + ".log")
        env = {
            **os.environ,
            "XDG_RUNTIME_DIR": str(runtime),
            "WAYLAND_DISPLAY": "wayland-1",
            "XDG_CURRENT_DESKTOP": desktop,
            "MOCK_WINDOWS": str(data),
            "MOCK_LOG": str(log),
            "MOCK_FOCUS_FAIL": "1" if focus_fail else "0",
            "PATH": str(fakebin) + os.pathsep + os.environ["PATH"],
        }
        if expect_wait:
            try:
                subprocess.run(["bash", str(HELPER)], env=env,
                               capture_output=True, text=True, timeout=0.8)
            except subprocess.TimeoutExpired:
                pass
            else:
                raise AssertionError(label + " should keep waiting for a valid Steam pair")
            result_code = -1
        else:
            run = subprocess.run(["bash", str(HELPER)], env=env,
                                 capture_output=True, text=True, timeout=5)
            assert not run.stderr, (label, run.stderr)
            result_code = run.returncode
        messages = log.read_text().splitlines() if log.exists() else []
        return result_code, messages

    rc, events = run_case("valid", windows)
    assert rc == 0, rc
    assert events == [
        "msg window-focus " + windows[0]["id"],
        "msg window-set-primary-extent 0.8",
    ], events

    resized = copy.deepcopy(windows)
    resized[0]["w"], resized[1]["w"] = 1567, 392
    rc, events = run_case("already-set", resized)
    assert rc == 0 and not events, events

    rc, events = run_case("wrong-compositor", windows, desktop="Hyprland")
    assert rc == 0 and not events, events

    reversed_pair = copy.deepcopy(windows)
    reversed_pair[0]["x"], reversed_pair[1]["x"] = 965, 7
    rc, events = run_case("wrong-order", reversed_pair, expect_wait=True)
    assert not events, events

    invisible = copy.deepcopy(windows)
    invisible[0]["visible"] = False
    rc, events = run_case("hidden-workspace", invisible, expect_wait=True)
    assert not events, events

    floating = copy.deepcopy(windows)
    floating[1]["floating"] = True
    rc, events = run_case("floating-friends", floating, expect_wait=True)
    assert not events, events

    rc, events = run_case("focus-failure", windows, focus_fail=True)
    assert rc != 0, rc
    assert events == ["msg window-focus " + windows[0]["id"]], events

print("PASS: Umbriel Steam 80/20 action, no-op safety, and compositor dispatch")
