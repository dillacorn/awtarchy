#!/usr/bin/env python3
"""Run Sway's screenshot helper against isolated command mocks (no display)."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_SOURCE = ROOT / "trials/sway/capture.sh"
SOUND_SOURCE = ROOT / "config/hypr/scripts/screenshot_sound.sh"

with tempfile.TemporaryDirectory(prefix="sway-satty-contract-") as directory:
    root = Path(directory)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    (root / "run").mkdir()
    (root / "home").mkdir()
    trial = root / "trial"
    trial.mkdir()
    SCRIPT = trial / "capture.sh"
    shutil.copyfile(SCRIPT_SOURCE, SCRIPT)
    shutil.copyfile(SOUND_SOURCE, trial / "screenshot_sound.sh")
    events = root / "events"
    sound_events = root / "sound-events"
    sound_events.touch()

    mocks = {
        "pw-play": r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "--raw --format=s16 --rate=48000 --channels=1 --volume=0.35 --latency=20ms -" ]] || exit 8
stats="$(python3 -c 'import sys,hashlib; pcm=sys.stdin.buffer.read(); print(len(pcm), hashlib.sha256(pcm).hexdigest())')"
[[ "$stats" == "17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c" ]] || exit 9
[[ "${SOUND_FAIL:-0}" != 1 ]] || exit 10
printf 'shutter:%s\n' "$stats" >>"$SOUND_EVENTS"
""",
        "grim": r"""#!/usr/bin/env bash
set -euo pipefail
printf 'grim:%s\n' "$*" >>"$EVENTS"
[[ "$1" == "-g" || "$1" == "-o" ]] || exit 2
sleep "${GRIM_DELAY:-0}"
printf 'fakePNG' > "$3"
""",
        "slurp": r"""#!/usr/bin/env bash
set -euo pipefail
printf 'slurp:%s\n' "$*" >>"$EVENTS"
printf '10,20 300x200\n'
[[ ! -e /proc/self/fd/9 ]] || { printf 'slurp inherited screenshot lock\n' >&2; exit 13; }
sleep 2 >/dev/null 2>&1 &
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
[[ "$1" == "-r" && "$2" == "-t" ]] || exit 2
case "$3" in
    get_tree)
        printf '%s\n' '{"type":"root","nodes":[{"type":"workspace","nodes":[{"type":"con","id":3,"name":"Example","app_id":"example","visible":true,"rect":{"x":10,"y":20,"width":300,"height":200}}]}]}'
        ;;
    get_outputs)
        printf 'swaymsg:get_outputs\n' >>"$EVENTS"
        case "${FOCUSED_OUTPUT:-DP-3}" in
            DP-1)
                printf '%s\n' '[{"name":"DP-1","focused":true,"active":true},{"name":"DP-3","focused":false,"active":true}]' ;;
            DP-3)
                printf '%s\n' '[{"name":"DP-1","focused":false,"active":true},{"name":"DP-3","focused":true,"active":true}]' ;;
            none)
                printf '%s\n' '[{"name":"DP-1","focused":false,"active":true},{"name":"DP-3","focused":false,"active":true}]' ;;
            both)
                printf '%s\n' '[{"name":"DP-1","focused":true,"active":true},{"name":"DP-3","focused":true,"active":true}]' ;;
            inactive)
                printf '%s\n' '[{"name":"DP-1","focused":true,"active":false},{"name":"DP-3","focused":false,"active":true}]' ;;
            malformed)
                printf '%s\n' '{}' ;;
            *) exit 2 ;;
        esac ;;
    *) exit 2 ;;
esac
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
        "SOUND_EVENTS": str(sound_events),
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

    # Every successful Satty capture plays once before the editor opens.
    for _ in range(80):
        if len(sound_events.read_text().splitlines()) >= 4:
            break
        time.sleep(0.05)
    assert sound_events.read_text().splitlines() == [
        "shutter:17280 " + "baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"
    ] * 4
    sound_events.write_text("")

    # Super+Shift+D: directly capture the focused output, save PNG AND
    # clipboard, without slurp, Satty, or an output selection prompt.
    saved_files = []
    for selected in ("DP-1", "DP-3", "DP-3"):
        events.write_text("")
        clip_only = subprocess.run(
            ["bash", str(SCRIPT), "display-copy"],
            env=dict(env, FOCUSED_OUTPUT=selected),
            capture_output=True, text=True, timeout=10
        )
        assert clip_only.returncode == 0, (
            selected, clip_only.stdout, clip_only.stderr)
        lines = events.read_text().splitlines()
        assert lines[0] == "swaymsg:get_outputs", (selected, lines)
        assert lines[1].startswith(f"grim:-o {selected} "), (selected, lines)
        assert lines[2] == "clipboard", (selected, lines)
        assert len(lines) == 3, (selected, lines)
        assert all(not line.startswith(("slurp:", "satty:")) for line in lines)
        saved = sorted((root / "home/Pictures/Screenshots").glob("Screenshot-*.png"))
        assert len(saved) == len(saved_files) + 1
        assert all(p.read_bytes() == b"fakePNG" for p in saved)
        saved_files = saved
        assert "Saved screenshot and copied to clipboard" in clip_only.stdout
        assert not list((root / "run").glob("awtarchy-satty-*.png"))
    assert len(set(saved_files)) == 3, "Rapid captures must not overwrite"

    # Two overlapping keypresses must both save. Previously the second
    # process silently dropped the capture when flock was busy.
    events.write_text("")
    rapid_env = dict(env, FOCUSED_OUTPUT="DP-1", GRIM_DELAY="0.35")
    first = subprocess.Popen(
        ["bash", str(SCRIPT), "display-copy"], env=rapid_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    second = subprocess.Popen(
        ["bash", str(SCRIPT), "display-copy"], env=rapid_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    for capture in (first, second):
        stdout, stderr = capture.communicate(timeout=10)
        assert capture.returncode == 0, (stdout, stderr)
        assert "Saved screenshot and copied to clipboard" in stdout
    lines = events.read_text().splitlines()
    assert len(lines) == 6, lines
    assert all(lines[index] == "swaymsg:get_outputs" for index in (0, 3)), lines
    assert all(lines[index].startswith("grim:-o DP-1 ") for index in (1, 4)), lines
    assert lines[2] == lines[5] == "clipboard", lines
    assert len(list((root / "home/Pictures/Screenshots").glob("Screenshot-*.png"))) == 5

    # Audio playback is nonblocking and best-effort; five completed saves
    # must trigger five identical, selected shutter clicks, even during overlap.
    for _ in range(80):
        if len(sound_events.read_text().splitlines()) >= 5:
            break
        time.sleep(0.05)
    assert sound_events.read_text().splitlines() == ["shutter:17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"] * 5

    # Missing output or malformed IPC must not play a shutter sound.
    # No focused output or invalid IPC must fail safely: no capture or save.
    for invalid in ("none", "both", "inactive", "malformed"):
        events.write_text("")
        failed = subprocess.run(
            ["bash", str(SCRIPT), "display-copy"],
            env=dict(env, FOCUSED_OUTPUT=invalid),
            capture_output=True, text=True, timeout=10
        )
        assert failed.returncode != 0, (invalid, failed.stdout, failed.stderr)
        assert events.read_text().splitlines() == ["swaymsg:get_outputs"]
        assert len(list((root / "home/Pictures/Screenshots").glob("Screenshot-*.png"))) == 5
    assert sound_events.read_text().splitlines() == ["shutter:17280 baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"] * 5

    # Audio preferences can mute a single shortcut category without
    # changing the other categories, including after Satty is canceled.
    settings = trial / "screenshot_sound.sh"
    def sound_set(key, value):
        subprocess.run(["bash", str(settings), "set", key, value],
                       env=env, check=True, timeout=4)

    sound_set("satty", "false")
    count = len(sound_events.read_text().splitlines())
    satty_muted = subprocess.run(
        ["bash", str(SCRIPT), "area"], env=env,
        capture_output=True, text=True, timeout=10)
    assert satty_muted.returncode == 0
    time.sleep(0.15)
    assert len(sound_events.read_text().splitlines()) == count

    sound_set("print", "false")
    printed_muted = subprocess.run(
        ["bash", str(SCRIPT), "output"], env=env,
        capture_output=True, text=True, timeout=10)
    assert printed_muted.returncode == 0
    time.sleep(0.15)
    assert len(sound_events.read_text().splitlines()) == count

    # Direct capture still sounds while Satty and Print Screen are muted.
    direct_unmuted = subprocess.run(
        ["bash", str(SCRIPT), "display-copy"], env=env,
        capture_output=True, text=True, timeout=10)
    assert direct_unmuted.returncode == 0
    for _ in range(80):
        if len(sound_events.read_text().splitlines()) > count:
            break
        time.sleep(0.05)
    assert len(sound_events.read_text().splitlines()) == count + 1

    # Audio failure may not prevent a successful save+copy.
    success_without_audio = subprocess.run(
        ["bash", str(SCRIPT), "display-copy"],
        env=dict(env, FOCUSED_OUTPUT="DP-1", SOUND_FAIL="1"),
        capture_output=True, text=True, timeout=10
    )
    assert success_without_audio.returncode == 0
    assert len(list((root / "home/Pictures/Screenshots").glob("Screenshot-*.png"))) == 7

    # Super+Shift+F retains display picker and Satty (covered above).

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

print("PASS: Sway capture separates clipboard-only display from Satty and preserves safe capture locking")
