#!/usr/bin/env python3
"""Hyprland screenshot shortcut matches Sway's focused-monitor save+copy."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT / "config/hypr/scripts/screenshot_display.sh"
SWAY = ROOT / "trials/sway/capture.sh"
SWAY_CONFIG = ROOT / "trials/sway/config"

source = HYPR.read_text()
assert "hyprctl -j cursors" not in source
assert "hyprctl -j monitors" in source
assert "grim -o" in source
assert "wl-copy --type image/png" in source
assert "flock -w 5 9" in source
assert 'bash "$sound_helper" play direct 9>&-' in source
assert 'bash "$sound_helper" play "$sound_mode" 9>&-' in SWAY.read_text()
assert "screenshot_sound.sh" in source
assert "screenshot_sound.sh" in SWAY.read_text()
assert "notify-send " not in source
assert "satty" not in "\n".join(line for line in source.splitlines()
                                if not line.lstrip().startswith("#")).lower()
assert "display-copy" in SWAY.read_text()
assert SWAY_CONFIG.read_text().count(
    "Mod4+Shift+d exec bash $trial/capture.sh display-copy") == 2

with tempfile.TemporaryDirectory(prefix="awtarchy-focused-screenshot-") as temp:
    root = Path(temp)
    bin_dir = root / "bin"
    home = root / "home"
    bin_dir.mkdir()
    home.mkdir()
    (root / "run").mkdir()
    events = root / "events"
    events.touch()
    sound_events = root / "sound-events"
    sound_events.touch()

    mocks = {
        "pw-play": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "--raw --format=s16 --rate=48000 --channels=1 --volume=0.15 --latency=20ms -" ]] || exit 8
stats="$(python3 -c 'import sys,hashlib; pcm=sys.stdin.buffer.read(); print(len(pcm), hashlib.sha256(pcm).hexdigest())')"
[[ "$stats" == "17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c" ]] || exit 9
[[ "${SOUND_FAIL:-0}" != 1 ]] || exit 10
printf 'shutter:%s\n' "$stats" >>"$SOUND_EVENTS"
""",
        "hyprctl": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 2 && "$1" == "-j" && "$2" == monitors ]] || exit 4
printf 'hyprctl:%s\n' "$*" >> "$EVENTS"
case "${FOCUSED_MONITOR:-DP-3}" in
DP-1) printf '%s\n' '[{"name":"DP-1","focused":true},{"name":"DP-3","focused":false}]' ;;
DP-3) printf '%s\n' '[{"name":"DP-1","focused":false},{"name":"DP-3","focused":true}]' ;;
none) printf '%s\n' '[{"name":"DP-1","focused":false},{"name":"DP-3","focused":false}]' ;;
both) printf '%s\n' '[{"name":"DP-1","focused":true},{"name":"DP-3","focused":true}]' ;;
malformed) printf '%s\n' '{"unexpected":"value"}' ;;
*) exit 3 ;;
esac
""",
        "grim": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 3 && "$1" == "-o" ]] || exit 2
printf 'grim:%s\n' "$*" >> "$EVENTS"
[[ "${GRIM_FAIL:-0}" != 1 ]] || exit 15
sleep "${GRIM_DELAY:-0}"
printf 'PNG-for-%s' "$2" > "$3"
""",
        "wl-copy": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 2 && "$1" == --type && "$2" == image/png ]] || exit 2
printf 'clipboard:%s\n' "$(cat)" >> "$EVENTS"
[[ "${CLIP_FAIL:-0}" != 1 ]] || exit 21
""",
        "notify-send": r"""#!/usr/bin/env bash
set -euo pipefail
printf 'notify:%s\n' "$*" >> "$EVENTS"
""",
    }
    for name, body in mocks.items():
        path = bin_dir / name
        path.write_text(body)
        path.chmod(0o755)

    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
               HOME=str(home), XDG_RUNTIME_DIR=str(root / "run"),
               EVENTS=str(events), SOUND_EVENTS=str(sound_events))

    def run(**overrides):
        events.write_text("")
        return subprocess.run(["bash", str(HYPR)], env=dict(env, **overrides),
                              capture_output=True, text=True, timeout=8)

    def files():
        return list((home / "Pictures/Screenshots").glob("*.png"))

    for monitor in ("DP-3", "DP-1", "DP-3"):
        old_count = len(files())
        result = run(FOCUSED_MONITOR=monitor)
        assert result.returncode == 0, (result.stdout, result.stderr)
        lines = events.read_text().splitlines()
        assert lines[0] == "hyprctl:-j monitors", lines
        assert lines[1].startswith("grim:-o " + monitor + " "), lines
        assert lines[2] == "clipboard:PNG-for-" + monitor, lines
        assert len(lines) == 3, lines
        assert len(files()) == old_count + 1, files()
        assert sum(p.read_bytes() == ("PNG-for-" + monitor).encode()
                   for p in files()) >= 1

    assert len(set(p.name for p in files())) == 3, "Rapid captures overwrote"

    # Overlapping keypresses are queued, neither dropped nor interleaved.
    events.write_text("")
    rapid_env = dict(env, FOCUSED_MONITOR="DP-3", GRIM_DELAY="0.35")
    first = subprocess.Popen(
        ["bash", str(HYPR)], env=rapid_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    second = subprocess.Popen(
        ["bash", str(HYPR)], env=rapid_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for capture in (first, second):
        stdout, stderr = capture.communicate(timeout=10)
        assert capture.returncode == 0, (stdout, stderr)
    lines = events.read_text().splitlines()
    assert len(lines) == 6, lines
    assert lines[0] == lines[3] == "hyprctl:-j monitors", lines
    assert lines[1].startswith("grim:-o DP-3 "), lines
    assert lines[4].startswith("grim:-o DP-3 "), lines
    assert lines[2] == lines[5] == "clipboard:PNG-for-DP-3", lines
    assert len(files()) == 5
    assert len(set(p.name for p in files())) == 5

    # Playback starts only for successful saves and is fully detached from
    # the capture lock and the parent screenshot process.
    for _ in range(80):
        if len(sound_events.read_text().splitlines()) >= 5:
            break
        time.sleep(0.05)
    assert sound_events.read_text().splitlines() == ["shutter:17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"] * 5

    for monitor in ("none", "both", "malformed"):
        count = len(files())
        result = run(FOCUSED_MONITOR=monitor)
        assert result.returncode != 0
        assert events.read_text().splitlines() == ["hyprctl:-j monitors"]
        assert len(files()) == count

    before = len(files())
    failed = run(GRIM_FAIL="1")
    assert failed.returncode != 0
    assert len(files()) == before
    assert not any(line.startswith("clipboard:") for line in
                   events.read_text().splitlines())

    failed = run(CLIP_FAIL="1")
    assert failed.returncode != 0
    assert len(files()) == before + 1
    assert any(line.startswith("clipboard:") for line in
               events.read_text().splitlines())

    # Sound confirms successful capture, even if clipboard copying fails.
    for _ in range(80):
        if len(sound_events.read_text().splitlines()) >= 6:
            break
        time.sleep(0.05)
    assert sound_events.read_text().splitlines() == ["shutter:17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"] * 6

    # Missing or failing sound playback may never compromise the screenshot.
    successful = run(SOUND_FAIL="1")
    assert successful.returncode == 0
    assert len(files()) == before + 2
    for _ in range(20):
        time.sleep(0.02)
    assert sound_events.read_text().splitlines() == ["shutter:17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"] * 6

print("PASS: Hyprland focused display save+copy, unique filenames and capture-first sound")
