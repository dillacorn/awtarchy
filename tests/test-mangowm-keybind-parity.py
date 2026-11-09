#!/usr/bin/env python3
"""Static Awtarchy Hyprland -> Mango keyboard parity gates.

Do not confuse Mango parser success with complete/muscle-memory-compatible
desktop shortcuts: the first trial passed syntax while omitting launchers.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "config/hypr/hyprland.lua").read_text()
mango = (root / "config/mango/config.conf").read_text()
bridge = (root / "trials/mangowm/MangoBridge.qml").read_text()

assert 'ALT + SHIFT + RETURN' in source
assert 'SUPER + W' in source
assert 'SUPER + ALT + A' in source
assert 'SUPER + CTRL + X' in source

binds = {key: {} for key in ("default", "common", "noalt", "mouse", "vm")}
mode = "default"
for line_number, raw in enumerate(mango.splitlines(), 1):
    line = raw.strip()
    if line.startswith("key_mode="):
        mode = line.partition("=")[2]
        assert mode in binds, (line_number, mode)
    elif line.startswith(("bind=", "bindl=", "bindr=", "mousebind=")):
        kind, _, arguments = line.partition("=")
        parts = arguments.split(",", 2)
        assert len(parts) == 3, (line_number, line)
        mods, key, _ = parts
        identity = (kind, mods.upper(), key.lower())
        assert identity not in binds[mode], (mode, line_number, identity)
        binds[mode][identity] = line


def expect(mode, mods, key, action):
    identity = ("bind", mods.upper(), key.lower())
    assert identity in binds[mode], f"Mango {mode} missing {mods}+{key}"
    assert action in binds[mode][identity], (
        f"Mango {mode} wrong action for {mods}+{key}: "
        f"{binds[mode][identity]}"
    )


for mode in ("default", "noalt"):
    for mods, key, fragment in [
        ("ALT+SHIFT", "Return", "default_applications.py launch terminal"),
        ("SUPER", "Return", "default_applications.py launch terminal"),
        ("ALT", "P", "/mango/scripts/launcher.sh"),
        ("SUPER", "D", "/mango/scripts/launcher.sh"),
        ("SUPER+ALT", "A", "/hypr/scripts/default_applications.sh"),
        ("ALT+SHIFT", "C", "/hypr/scripts/qalc-terminal.sh"),
        ("ALT+SHIFT", "B", "launch_handler.sh btop"),
        ("SUPER", "W", "/mango/scripts/wallpicker.sh"),
        ("SUPER+CTRL", "M", "wdisplays"),
        ("SUPER", "I", "/mango/scripts/color-picker.py"),
        ("SUPER+ALT", "Q", "killclient,force"),
        ("SUPER+ALT", "equal", "hypr-ddc-brightness.sh up 5"),
        ("SUPER+ALT", "minus", "hypr-ddc-brightness.sh down 5"),
        ("SUPER+SHIFT", "W", "awtwall --random-current"),
        ("SUPER+CTRL", "W", "/mango/scripts/wallpicker.sh random-all"),
        ("SUPER+ALT", "W", "/mango/scripts/wallpicker.sh random-all-different"),
        ("SUPER", "T", "theme_select.sh"),
        ("SUPER", "C", "quickshell_clipboard_toggle.sh"),
        ("SUPER", "N", "quickshell_notifications_toggle.sh"),
        ("SUPER+ALT", "B", "quickshell_bar_rotate.sh"),
        ("SUPER+CTRL", "B", "quickshell_bar_flip.sh"),
        ("SUPER+ALT", "BackSpace", "quickshell_quick_settings_toggle.sh"),
        ("SUPER", "Space", "quickshell_notification_dismiss.sh"),
        ("SUPER", "P", "/mango/scripts/power.sh"),
        ("SUPER", "S", "qr_scan.sh"),
        ("SUPER+SHIFT", "G", "gif_capture.sh"),
        ("SUPER+SHIFT", "F", "/mango/scripts/capture.sh output"),
        ("SUPER+SHIFT", "S", "/mango/scripts/capture.sh window"),
        ("SUPER", "X", "toggle_special_tag"),
        ("SUPER+CTRL", "X", "tag_special_tag"),
    ]:
        expect(mode, mods, key, fragment)
    for number in range(1, 11):
        key = str(number % 10)
        expect(mode, "SUPER", key, f"view,{number}")
        expect(mode, "SUPER+SHIFT", key, f"tag,{number}")

for mods, key, command in [
    ("SUPER+ALT", "N", "keymode.sh toggle noalt"),
    ("SUPER+ALT", "M", "keymode.sh toggle mouse"),
    ("SUPER+ALT", "V", "keymode.sh toggle vm"),
]:
    expect("common", mods, key, command)

for key, fragment in [("P", "launcher.sh"), ("A", "default_applications.sh"),
                      ("Return", "default_applications.py launch terminal")]:
    expect("vm", "SUPER+ALT", key, fragment)
expect("vm", "SUPER+ALT", "S", "capture.sh window")
expect("vm", "SUPER+ALT+CTRL", "S", "qr_scan.sh")
for mods, key, fragment in [
    ("SUPER+ALT", "btn_left", "moveresize,curmove"),
    ("SUPER+ALT", "btn_right", "moveresize,curresize"),
    ("SUPER+ALT", "btn_middle", "togglefloating"),
]:
    identity = ("mousebind", mods, key)
    assert identity in binds["vm"], identity
    assert fragment in binds["vm"][identity], identity

# Mango's resizewin dispatcher requires explicit +0 instead of bare 0:
# bare 0 makes an absolute zero dimension for floating windows.
resize_count = 0
for mode in ("default", "noalt"):
    for entry in binds[mode].values():
        if ",resizewin," not in entry:
            continue
        delta = entry.split(",resizewin,", 1)[1].split(",")
        assert len(delta) == 2 and all(
            part.startswith(("+", "-")) and part[1:].isdigit()
            for part in delta
        ), (mode, entry)
        resize_count += 1
assert resize_count >= 25, resize_count

assert "wdisplays" in (root / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
assert (root / "config/mango/scripts/monitor-info.sh").is_file()

# No compositor-specific shrinking or pointer jump when ALT/SUPER dragging
# tiled/floating windows. Mango 0.18.5 otherwise shrinks tiled drags to
# 300x300 and warps pointer to a resize corner.
expected_drag_options = {
    "drag_tile_to_tile": "1",
    "drag_tile_small": "0",
    "drag_warp_cursor": "0",
}
drag_options = {}
for raw in mango.splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key in expected_drag_options:
        assert key not in drag_options, f"Duplicate Mango drag option {key}"
        drag_options[key] = value
assert drag_options == expected_drag_options, drag_options

for mode in ("default", "noalt"):
    for mod in ("SUPER",) if mode == "noalt" else ("SUPER", "ALT"):
        for button, action in (("btn_left", "moveresize,curmove"),
                               ("btn_right", "moveresize,curresize")):
            assert ("mousebind", mod, button) in binds[mode], (
                mode, mod, button)
            assert action in binds[mode][("mousebind", mod, button)], (
                mode, mod, button)
for button, action in (("btn_left", "moveresize,curmove"),
                       ("btn_right", "moveresize,curresize")):
    assert action in binds["mouse"][("mousebind", "SUPER", button)]

# One-to-one viewport workspaces; no overview shadowing the original
# SUPER+SPACE notification-dismiss action.
assert not any("toggleoverview" in line for group in binds.values()
               for line in group.values())
assert all("hyprctl" not in line for group in binds.values()
           for line in group.values())
# A valid config without native event updates is too slow for this UI.
assert '["mmsg", "watch", "all-monitors"]' in bridge
assert '["mmsg", "watch", "all-clients"]' in bridge
assert "interval: 750" not in bridge
assert len(binds["default"]) >= 150, len(binds["default"])
assert len(binds["noalt"]) >= 95, len(binds["noalt"])
print("PASS: Mango keybind parity, Hypr-like drag defaults, native event streaming")
