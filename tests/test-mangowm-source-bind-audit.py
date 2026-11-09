#!/usr/bin/env python3
"""Compare every literal Hyprland ALT/SUPER shortcut with Mango equivalents.

Source-audit for current Lua (including arrays used by hl.bind). Generated
workspace/direction/resize loops are covered in keybind-parity.py. Missing
keys must be explicitly acknowledged; never silently discard a new binding.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
lua = (root / "config/hypr/hyprland.lua").read_text()
mango = (root / "config/mango/config.conf").read_text()

def normalize(parts):
    chunks = [part.strip().upper() for part in parts.split("+")]
    key = chunks.pop()
    return "+".join(sorted(chunks) + [key])

def original(section):
    pattern = re.compile(r'"((?:ALT|SUPER)(?: \+ [A-Za-z0-9:_-]+)+)"')
    return {normalize(match.group(1)) for match in pattern.finditer(section)}

default_start = lua.index("-- DEFAULT MODE")
noalt_start = lua.index('hl.define_submap("noalt"')
mouse_start = lua.index('hl.define_submap("mouse"')
vm_start = lua.index('hl.define_submap("vm"')
vm_end = lua.index("-- RULES", vm_start)
originals = {
    "default": original(lua[default_start:noalt_start]),
    "noalt": original(lua[noalt_start:mouse_start]),
    "vm": original(lua[vm_start:vm_end]),
}

modes = {name: set() for name in ("default", "noalt", "mouse", "vm", "common")}
active = "default"
mouse_mapping = {"BTN_LEFT": "MOUSE:272", "BTN_RIGHT": "MOUSE:273",
                 "BTN_MIDDLE": "MOUSE:274"}
for raw in mango.splitlines():
    line = raw.strip()
    if line.startswith("key_mode="):
        active = line.split("=", 1)[1]
        assert active in modes, active
    elif line.startswith(("bind=", "mousebind=")):
        op, fields = line.split("=", 1)
        modifiers, key, *_ = fields.split(",")
        if op == "mousebind":
            key = mouse_mapping.get(key.upper(), key)
        modes[active].add(normalize(modifiers + "+" + key))

# No Mango equivalent with the same user-facing action. These must be
# removed from the exception list when a native implementation is added.
unsupported = {
    "SUPER+ALT+T",                              # Hyprbars
    "SUPER+ALT+CTRL+BRACKETRIGHT",              # Hyprsunset increment
    "SUPER+ALT+CTRL+BRACKETLEFT",               # Hyprsunset decrement
    "SUPER+ALT+CTRL+N",                         # Hyprsunset toggle
    "SUPER+ALT+BRACKETRIGHT",                   # Vibrance shader
    "SUPER+ALT+BRACKETLEFT",
    "SUPER+ALT+BACKSLASH",
    "SUPER+ALT+CTRL+V",
    "SUPER+ALT+CTRL+F",                         # Workspace mix
    "SUPER+ALT+CTRL+R",
    "SUPER+EQUAL",                              # Hyprland scene zoom
    "SUPER+MINUS",
    "SUPER+SHIFT+EQUAL",
    "SUPER+SHIFT+MINUS",
    "SUPER+BACKSPACE",
    "SUPER+BACKSLASH",
    "SUPER+CTRL+EQUAL",
    "SUPER+CTRL+MINUS",
}
unsupported = {normalize(key) for key in unsupported}
assert len(unsupported) == 18

for mode, found in originals.items():
    assert len(found) >= {"default": 90, "noalt": 85, "vm": 18}[mode]
    missing = found - modes[mode] - modes["common"]
    expected = unsupported if mode in ("default", "noalt") else set()
    assert missing == expected, (
        f"{mode} key migration drift; unaccounted={sorted(missing-expected)} "
        f"or stale unsupported={sorted(expected-missing)}"
    )
print("PASS: literal Hyprland bind coverage, 18 explicitly documented "
      "non-equivalents, mouse and VM modes")
