#!/usr/bin/env python3
"""Conservatively translate saved Awtarchy Hyprland/Sway settings to Umbriel.

No Lua, shell, or source compositor command is executed. Unknown bindings,
dynamic monitor policies, and disconnected outputs are intentionally skipped.
The result is a separate include, not an edit to either source compositor.
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import subprocess
import tomllib
from decimal import Decimal, InvalidOperation

CONNECTOR = re.compile(r"[A-Za-z0-9_.-]{1,48}\Z")
MODE = re.compile(r"(\d{3,5})x(\d{3,5})@(\d+(?:\.\d+)?)\Z")
POSITION = re.compile(r"(-?\d+)x(-?\d+)\Z")
TRANSFORMS = ("normal", "90", "180", "270", "flipped",
              "flipped-90", "flipped-180", "flipped-270")

# Only these source application actions have known Umbriel-safe replacements.
IPC = "bash ~/.config/umbriel/awtarchy-trial/ipc.sh "
COMMANDS = {
    "app_launcher": "spawn " + IPC + "launcher toggle",
    "notifications_toggle": "spawn " + IPC + "notifications toggle",
    "clipboard_history": "spawn " + IPC + "clipboard toggle",
    "hypr_quicksettings": "spawn " + IPC + "quicksettings toggle",
    "theme_select": "spawn " + IPC + "themes toggle",
    "terminal": "spawn foot",
    "btop": "spawn foot btop",
    "yazi": "spawn foot yazi",
    "calculator": "spawn foot --app-id awtarchy-qalc qalc",
    "wiremix": "spawn foot wiremix",
    "file_manager": "spawn python3 ~/.config/hypr/scripts/default_applications.py launch file-manager",
    "web_browser": "spawn python3 ~/.config/hypr/scripts/default_applications.py launch browser",
    "power_menu": "spawn " + IPC + "powermenu begin",
    "default_apps": "spawn python3 ~/.config/hypr/scripts/default_applications.py",
}
NATIVE = {
    "hl.dsp.window.close()": "window-close",
    'hl.dsp.window.float({ action = "toggle" })': "window-toggle-floating",
    'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })':
        "window-toggle-fullscreen",
    "hl.dsp.window.pin()": "window-toggle-pinned",
    "hl.dsp.window.cycle_next({ next = true })": "window-focus-next",
    "hl.dsp.window.cycle_next({ next = false })": "window-focus-previous",
    'hl.dsp.workspace.toggle_special("magic")': "scratchpad-toggle",
}
KEYS = {"SUPER": "Mod", "ALT": "Alt", "CTRL": "Ctrl",
        "CONTROL": "Ctrl", "SHIFT": "Shift"}
KEYNAMES = {"return": "Return", "backspace": "BackSpace", "tab": "Tab",
            "escape": "Escape", "space": "Space", "bracketleft": "BracketLeft",
            "bracketright": "BracketRight", "equal": "Equal",
            "minus": "Minus", "left": "Left", "right": "Right",
            "up": "Up", "down": "Down", "f4": "F4"}
SAFE_EXEC = {
    "foot": "spawn foot",
    "foot yazi": "spawn foot yazi",
    "fuzzel": "spawn fuzzel",
    "smtty -S -l": "spawn smtty -S -l",
    "smtty -k": "spawn smtty -k",
    "bash $trial/ipc.sh launcher toggle": COMMANDS["app_launcher"],
    "bash $trial/ipc.sh notifications toggle": COMMANDS["notifications_toggle"],
    "bash $trial/ipc.sh clipboard toggle": COMMANDS["clipboard_history"],
    "bash $trial/ipc.sh powermenu begin": COMMANDS["power_menu"],
    "bash $trial/ipc.sh quicksettings toggle": COMMANDS["hypr_quicksettings"],
    "bash $trial/ipc.sh themes toggle": COMMANDS["theme_select"],
}


def safe_read(path: Path, limit: int = 1024 * 1024) -> str | None:
    if (path.is_symlink() or not path.is_file()
            or path.stat().st_size > limit or path.stat().st_uid != os.geteuid()):
        return None
    return path.read_text(encoding="utf-8")


def connected_outputs() -> set[str]:
    """Prefer the active Umbriel connector inventory, else Linux DRM."""
    if os.environ.get("XDG_CURRENT_DESKTOP", "").lower() == "umbriel":
        try:
            response = subprocess.run(["umbriel", "outputs", "--json"],
                                      text=True, capture_output=True,
                                      check=True, timeout=5)
            data = json.loads(response.stdout)
            if isinstance(data, dict):
                data = data.get("ok", data.get("outputs"))
            if isinstance(data, list):
                names = {item["name"] for item in data if
                         isinstance(item, dict) and isinstance(item.get("name"), str)
                         and CONNECTOR.fullmatch(item["name"])}
                if names:
                    return names
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError,
                subprocess.TimeoutExpired):
            pass
    names = set()
    for status in Path("/sys/class/drm").glob("card*-*/status"):
        match = re.fullmatch(r"card\d+-(.+)", status.parent.name)
        if match and CONNECTOR.fullmatch(match.group(1)):
            try:
                if status.read_text(encoding="ascii").strip() == "connected":
                    names.add(match.group(1))
            except OSError:
                continue
    return names


def output(name: str, mode: str, position: str, scale: str,
           vrr: str = "0", transform: str = "normal") -> dict | None:
    match = MODE.fullmatch(mode)
    pos = POSITION.fullmatch(position)
    if not name or not CONNECTOR.fullmatch(name) or not match or not pos:
        return None
    try:
        hz, factor = Decimal(match.group(3)), Decimal(scale)
    except InvalidOperation:
        return None
    if not (20 <= hz <= 1000 and Decimal("0.25") <= factor <= 4
            and 320 <= int(match.group(1)) <= 20000
            and 200 <= int(match.group(2)) <= 20000):
        return None
    if transform not in TRANSFORMS:
        return None
    if vrr not in ("0", "1", "2"):
        return None
    result = {"mode": mode, "position": [int(pos.group(1)),
              int(pos.group(2))], "scale": float(factor)}
    if transform != "normal":
        result["transform"] = transform
    if vrr == "1":
        result["vrr"] = "always"
    elif vrr == "2":
        result["vrr"] = "fullscreen"
    return result


def saved_hyprmoncfg_outputs(home: Path, connected: set[str]) -> dict[str, dict]:
    """Use a saved hyprmoncfg profile only when it matches unambiguously.

    Canonical hyprmoncfg profiles are JSON, not the generated live Lua.
    Never choose between divergent saved profiles or guess connector names.
    """
    directory = home / ".config/hyprmoncfg/profiles"
    if (not connected or directory.is_symlink() or not directory.is_dir()
            or directory.stat().st_uid != os.geteuid()):
        return {}
    possibilities = {}
    for path in sorted(directory.glob("*.json"))[:65]:
        text = safe_read(path, 262144)
        if text is None:
            continue
        try:
            profile = json.loads(text)
        except ValueError:
            continue
        if not isinstance(profile, dict):
            continue
        entries = profile.get("outputs")
        if not isinstance(entries, list) or not 0 < len(entries) <= 32:
            continue
        results, names = {}, set()
        valid = True
        for value in entries:
            if not isinstance(value, dict):
                valid = False
                break
            name = value.get("name")
            enabled = value.get("enabled")
            if (not isinstance(name, str) or not CONNECTOR.fullmatch(name)
                    or name in names or type(enabled) is not bool):
                valid = False
                break
            names.add(name)
            if name not in connected:
                continue
            if not enabled:
                results[name] = {"enabled": False}
                continue
            x, y = value.get("x"), value.get("y")
            if type(x) is not int or type(y) is not int:
                valid = False
                break
            if value.get("rotation_auto") or value.get("mirror"):
                valid = False
                break
            mode = value.get("mode", "")
            if not isinstance(mode, str) or not MODE.fullmatch(mode):
                width, height, hz = (value.get("width"), value.get("height"),
                                     value.get("refresh"))
                if (type(width) is not int or type(height) is not int
                        or type(hz) not in (int, float)):
                    valid = False
                    break
                mode = f"{width}x{height}@{hz}"
            scale = value.get("scale")
            if type(scale) not in (int, float):
                valid = False
                break
            rotation = value.get("transform", 0)
            if type(rotation) is not int or not 0 <= rotation < len(TRANSFORMS):
                valid = False
                break
            vrr = value.get("vrr", 0)
            settings = output(name, mode, f"{x}x{y}", str(scale),
                              str(vrr) if vrr in (0, 1, 2) else "0",
                              TRANSFORMS[rotation])
            if settings is None:
                valid = False
                break
            results[name] = settings
        if not valid or names != connected or set(results) != connected:
            continue
        signature = json.dumps(results, sort_keys=True, separators=(",", ":"))
        possibilities[signature] = results
    # Two profiles with the same outputs but different layouts are ambiguous.
    return next(iter(possibilities.values())) if len(possibilities) == 1 else {}


def hypr_outputs(home: Path, connected: set[str]) -> dict[str, dict]:
    # hyprmoncfg's generated active Lua is more authoritative than the
    # Awtarchy root wildcard and sample Virtual-1 entries.
    configs = (home / ".config/hypr/hyprmoncfg-monitors.lua",
               home / ".config/hypr/hyprland.lua")
    for path in configs:
        text = safe_read(path)
        if text is None:
            continue
        result = {}
        for line in text.splitlines():
            if line.lstrip().startswith("--"):
                continue
            match = re.fullmatch(r'\s*hl\.monitor\(\{(.*?)\}\)\s*(?:--.*)?', line)
            if not match:
                continue
            fields = {}
            data = match.group(1).strip().rstrip(",").strip()
            pattern = re.compile(
                r"""\s*(output|mode|position|scale|vrr|transform)\s*=\s*("[^"]*"|'[^']*'|-?\d+(?:\.\d+)?)\s*(?:,|$)"""
            )
            at = 0
            while at < len(data):
                item = pattern.match(data, at)
                if item is None or item.group(1) in fields:
                    fields = {}
                    break
                value = item.group(2)
                fields[item.group(1)] = value[1:-1] if value[0] in ("'", '"') else value
                at = item.end()
            name = fields.get("output", "")
            if name not in connected:
                continue
            rotate = fields.get("transform", "0")
            transform = (TRANSFORMS[int(rotate)]
                         if rotate.isdecimal() and int(rotate) < len(TRANSFORMS)
                         else "normal")
            settings = output(name, fields.get("mode", ""), fields.get("position", ""),
                              fields.get("scale", ""), fields.get("vrr", "0"), transform)
            if settings:
                result[name] = settings
        if result:
            return result
    return saved_hyprmoncfg_outputs(home, connected)


def sway_outputs(home: Path, connected: set[str]) -> dict[str, dict]:
    paths = [home / ".config/sway/awtarchy-trial/outputs",
             home / ".config/sway/awtarchy-trial/config"]
    values: dict[str, dict] = {}
    for path in paths:
        text = safe_read(path)
        if text is None:
            continue
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            m = re.fullmatch(
                r"\s*output\s+([A-Za-z0-9_.-]+)\s+mode\s+"
                r"(\d{3,5}x\d{3,5}@\d+(?:\.\d+)?)Hz\s+"
                r"position\s+(-?\d+)\s+(-?\d+)\s+scale\s+(\d+(?:\.\d+)?)\s*",
                line)
            if m and m.group(1) in connected:
                value = output(m.group(1), m.group(2),
                               m.group(3) + "x" + m.group(4), m.group(5))
                if value:
                    values[m.group(1)] = value
            v = re.fullmatch(r"\s*output\s+([A-Za-z0-9_.-]+)\s+adaptive_sync\s+on\s*", line)
            if v and v.group(1) in values:
                values[v.group(1)]["vrr"] = "always"
    return values


def normalize_key(raw: str, sway: bool = False) -> str | None:
    pieces = [p.strip() for p in raw.split("+")]
    if not pieces or len(pieces) > 5 or any(not p for p in pieces):
        return None
    modifiers = []
    for piece in pieces[:-1]:
        name = ({"MOD4": "Mod", "MOD1": "Alt", "CONTROL": "Ctrl"}.get(piece.upper())
                if sway else KEYS.get(piece.upper()))
        name = name or KEYS.get(piece.upper())
        if not name or name in modifiers:
            return None
        modifiers.append(name)
    last = pieces[-1]
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,30}", last):
        return None
    if last.lower() in KEYNAMES:
        key = KEYNAMES[last.lower()]
    elif len(last) == 1:
        key = last.upper()
    elif last.startswith("XF86"):
        key = last
    else:
        key = last[:1].upper() + last[1:]
    return "+".join(modifiers + [key])


def hypr_bindings(home: Path) -> dict[str, str]:
    text = safe_read(home / ".config/hypr/hyprland.lua")
    if not text:
        return {}
    # The noalt submap is a different keyboard mode. Import only the
    # default binding table rather than combining incompatible alternatives.
    text = text.split('hl.define_submap("noalt", function()', 1)[0]
    binds = {}

    def add(raw: str, action: str | None):
        chord = normalize_key(raw)
        if chord and action:
            binds[chord] = action

    # Literal key/known action pairs inside the Awtarchy keybinding tables.
    for match in re.finditer(
            r'\{\s*"([A-Za-z0-9 +_-]+)"\s*,\s*([A-Za-z_][A-Za-z_0-9]*)\s*(?:,|\})',
            text):
        add(match.group(1), COMMANDS.get(match.group(2)))
    # Default Awtarchy window bindings live in array tables rather than
    # direct hl.bind calls; translate only exact, supported dispatcher calls.
    # This preserves the user's ALT/SUPER window close, float, fullscreen,
    # focus cycling and pin shortcuts without evaluating any Lua.
    for line in text.splitlines():
        if line.lstrip().startswith("--"):
            continue
        item = re.fullmatch(
            r'\s*\{\s*"([^"]+)"\s*,\s*(hl\.dsp\..+?)\s*\}\s*,?\s*(?:--.*)?',
            line)
        if item:
            add(item.group(1), NATIVE.get(item.group(2).strip()))
    # Only literal, non-executed hl.bind actions. Complex Lua callbacks,
    # submaps, and Hyprland-only commands are not portable.
    for match in re.finditer(
            r'hl\.bind\("([^"]+)",\s*hl\.dsp\.exec_cmd\(([A-Za-z_][A-Za-z_0-9]*)\)',
            text):
        add(match.group(1), COMMANDS.get(match.group(2)))
    for match in re.finditer(
            r'hl\.bind\("([^"]+)",\s*(hl\.dsp\.[^\n]+?)\s*,\s*\{',
            text):
        add(match.group(1), NATIVE.get(match.group(2).strip()))
    # Static default-mode actions with callback bodies verified in Awtarchy.
    if 'hl.bind("SUPER + P", function()' in text and 'hl.dsp.exec_cmd(power_menu)' in text:
        add("SUPER + P", COMMANDS["power_menu"])
    # Generated movement/workspace loops use the same two modifiers. Only
    # replicate them if their source construction is actually present.
    if 'hl.dsp.focus({ direction = direction })' in text:
        for direction in ("left", "right", "up", "down"):
            for mod in ("ALT", "SUPER"):
                add(f"{mod} + {direction}", "window-focus-" + direction)
    if 'hl.dsp.window.move({ direction = direction })' in text:
        for direction in ("left", "right", "up", "down"):
            for mod in ("ALT", "SUPER"):
                add(f"{mod} + SHIFT + {direction}", "window-move-" + direction)
    if 'hl.dsp.focus({ workspace = workspace })' in text:
        for number in range(1, 11):
            key = number % 10
            for mod in ("ALT", "SUPER"):
                add(f"{mod} + {key}", f"workspace-switch {number}")
    if 'scratchpad_move_active_to_workspace(workspace)' in text:
        for number in range(1, 11):
            key = number % 10
            for mod in ("ALT", "SUPER"):
                add(f"{mod} + SHIFT + {key}", f"window-move-to-workspace {number}")
    return binds


def sway_bindings(home: Path) -> dict[str, str]:
    text = safe_read(home / ".config/sway/awtarchy-trial/config")
    if not text:
        return {}
    result = {}
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"\s*bindsym\s+([A-Za-z0-9_+-]+)\s+(.+?)\s*", line)
        if not match:
            continue
        chord = normalize_key(match.group(1), sway=True)
        if not chord:
            continue
        action = match.group(2)
        target = None
        if action.startswith("exec "):
            target = SAFE_EXEC.get(action[5:])
        elif action == "kill":
            target = "window-close"
        elif action == "floating toggle":
            target = "window-toggle-floating"
        elif action == "fullscreen toggle":
            target = "window-toggle-fullscreen"
        elif action == "scratchpad show":
            target = "scratchpad-toggle"
        elif action == "move scratchpad":
            target = "window-move-to-scratchpad"
        elif action == "sticky toggle":
            target = "window-toggle-pinned"
        elif re.fullmatch(r"focus (left|right|up|down)", action):
            target = "window-focus-" + action.split()[-1]
        elif re.fullmatch(r"move (left|right|up|down)", action):
            target = "window-move-" + action.split()[-1]
        elif (n := re.fullmatch(r"workspace number ([1-9]|10)", action)):
            target = "workspace-switch " + n.group(1)
        elif (n := re.fullmatch(r"move container to workspace number ([1-9]|10)", action)):
            target = "window-move-to-workspace " + n.group(1)
        if target:
            result[chord] = target
    return result


def select_source(home: Path, choice: str = "auto") -> tuple[str, str]:
    if choice not in ("auto", "hyprland", "sway"):
        raise ValueError("Unknown migration source")
    if choice != "auto":
        return choice, "explicit user choice"
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if desktop.startswith("hyprland"):
        return "hyprland", "current Hyprland session"
    if desktop.startswith("sway"):
        return "sway", "current Sway session"
    # The first Umbriel install predates a last-session marker. Do not guess
    # based on mtimes or inspect private login history. Prefer Awtarchy's
    # existing primary Hyprland config until a source is explicitly chosen.
    marker = home / ".local/state/awtarchy/last-compositor"
    value = safe_read(marker, 100)
    if value and value.strip().lower() in ("hyprland", "sway"):
        return value.strip().lower(), "recorded last used compositor"
    if safe_read(home / ".config/hypr/hyprland.lua"):
        return "hyprland", "saved Awtarchy primary config (last use unknown)"
    if safe_read(home / ".config/sway/awtarchy-trial/config"):
        return "sway", "only saved supported source config"
    return "none", "no known source configuration"


def live_umbriel_scales(connected: set[str]) -> dict[str, float]:
    """Preserve verified wdisplays changes instead of stale saved Hyprland DPI."""
    if os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel":
        return {}
    try:
        response = subprocess.run(["umbriel", "outputs", "--json"], check=True,
                                  capture_output=True, text=True, timeout=5)
        data = json.loads(response.stdout)
        if isinstance(data, dict):
            data = data.get("ok", data.get("outputs"))
        if not isinstance(data, list):
            return {}
        scales = {}
        for output in data:
            if not isinstance(output, dict) or output.get("enabled") is not True:
                continue
            name, value = output.get("name"), output.get("scale")
            if name in connected and type(value) in (int, float):
                value = float(value)
                if math.isfinite(value) and 0.25 <= value <= 4:
                    scales[name] = value
        return scales
    except (OSError, ValueError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {}


def migrate(home: Path, source: str = "auto",
            connected: set[str] | None = None) -> tuple[bytes, dict]:
    selected, reason = select_source(home, source)
    names = connected_outputs() if connected is None else connected
    if selected == "hyprland":
        displays = hypr_outputs(home, names)
        bindings = hypr_bindings(home)
    elif selected == "sway":
        displays = sway_outputs(home, names)
        bindings = sway_bindings(home)
    else:
        displays, bindings = {}, {}
    # The saved source may describe a profile not presently active. Do not
    # propagate its fractional scale into a new Umbriel session unverified.
    # When running Umbriel, the current physical output state takes priority,
    # including wdisplays scale corrections the user has just made.
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").casefold()
    active_source = (selected == "hyprland" and desktop.startswith("hyprland")
                     or selected == "sway" and desktop.startswith("sway"))
    live_scales = live_umbriel_scales(names)
    lines = ["# Generated by Awtarchy from the saved " + selected + " profile.",
             "# Connected outputs use 10 fixed workspaces and allow game-requested tearing.",
             "# Running Umbriel scale overrides saved profiles; otherwise 1.0 is the fallback.",
             "# Personal configurations are preserved by the managed-checksum staging process.",
             ""]
    for name in sorted(names):
        settings = dict(displays.get(name, {}))
        if not active_source:
            settings["scale"] = 1.0
        settings["scale"] = live_scales.get(name, settings.get("scale", 1.0))
        settings["workspaces"] = 10
        # Output opt-in alone does not force tearing: only clients that request
        # it (or match a game rule) may use asynchronous fullscreen flips.
        settings["tearing"] = True
        lines.append("[output." + json.dumps(name) + "]")
        for field, value in settings.items():
            lines.append(field + " = " + json.dumps(value, ensure_ascii=True))
        lines.append("")
    if bindings:
        lines.append("[keybinds]")
        for chord, command in sorted(bindings.items()):
            lines.append(json.dumps(chord) + " = " + json.dumps(command))
        lines.append("")
    result = ("\n".join(lines) + "\n").encode()
    tomllib.loads(result.decode("utf-8"))
    return result, {"source": selected, "selection": reason,
                    "outputs": len(displays), "keybinds": len(bindings),
                    "live_scales": live_scales,
                    "connected_outputs": sorted(names)}


if __name__ == "__main__":
    import argparse
    import sys
    p = argparse.ArgumentParser()
    p.add_argument("--source", choices=["auto", "hyprland", "sway"], default="auto")
    p.add_argument("--show", action="store_true")
    args = p.parse_args()
    try:
        body, info = migrate(Path.home(), args.source)
        print("Migration source: " + info["source"] + " (" + info["selection"] + ")")
        print("Connected: " + ", ".join(info["connected_outputs"]))
        print("Translated: " + str(info["outputs"]) + " outputs, " +
              str(info["keybinds"]) + " shortcuts")
        if args.show:
            print(body.decode())
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as e:
        print("Umbriel migration: " + str(e), file=sys.stderr)
        sys.exit(1)
