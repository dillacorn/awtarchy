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
        ("SUPER", "W", "awtwall --resume"),
        ("SUPER+SHIFT", "W", "awtwall --random-current"),
        ("SUPER+CTRL", "W", "awtwall --random-all"),
        ("SUPER+ALT", "W", "awtwall --random-all-different"),
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
print("PASS: Mango Awtarchy keyboard parity, mode isolation, native event streaming")
