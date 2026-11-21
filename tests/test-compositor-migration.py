#!/usr/bin/env python3
"""Offline translation coverage: exact modes, safe shortcuts and source choice."""
from pathlib import Path
import json
import importlib.util
import os
import tempfile
import tomllib
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "awtarchy_umbriel_migration", ROOT / "compositors/umbriel/migrate.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="awtarchy-migration-") as d:
    home = Path(d)
    hypr = home / ".config/hypr/hyprland.lua"
    hypr.parent.mkdir(parents=True)
    hypr.write_text(
        'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", vrr = 0 })\n'
        'hl.monitor({ output = "Virtual-1", mode = "1600x900@60", position = "auto", scale = 1, vrr = 0 })\n'
        'hl.monitor({ output = "DP-1", mode = "1920x1080@400.002014", position = "0x1080", scale = 1, vrr = 0 })\n'
        'hl.monitor({ output = "DP-3", mode = "1920x1080@239.761002", position = "0x0", scale = 1, vrr = 1 })\n'
        'hl.bind("SUPER + Q", hl.dsp.window.close(), {})\n'
        'hl.bind("SUPER + F", hl.dsp.window.float({ action = "toggle" }), {})\n'
        'hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), {})\n'
        'hl.bind("SUPER + N", hl.dsp.exec_cmd(notifications_toggle), {})\n'
        'hl.bind("SUPER + ALT + backspace", hl.dsp.exec_cmd(hypr_quicksettings), {})\n'
        'hl.bind("SUPER + X", hl.dsp.workspace.toggle_special("magic"), {})\n'
        'hl.bind("SUPER + ALT + bracketleft", hl.dsp.exec_cmd(vibrance_shader .. " down"), {})\n'
        'hl.bind("SUPER + ALT + CTRL + F12", hl.dsp.exec_cmd("notify-send hacked"), {})\n'
        'hl.bind("ALT + P", hl.dsp.exec_cmd(app_launcher), {})\n'
        'hl.bind("SUPER + E", hl.dsp.exec_cmd(file_manager), {})\n'
        'hl.bind("SUPER + P", function()\n'
        '  hl.dispatch(hl.dsp.exec_cmd(power_menu))\n'
        'end, {})\n'
        'for _, bind in ipairs(workspace_keys) do\n'
        '  hl.bind("ALT + " .. key, hl.dsp.focus({ workspace = workspace }), {})\n'
        '  hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = workspace }), {})\n'
        '  hl.bind("ALT + SHIFT + " .. key, function()\n'
        '    scratchpad_move_active_to_workspace(workspace)\n'
        '  end, {})\n'
        'end\n',
        encoding="utf-8")
    connected = {"DP-1", "DP-3"}
    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel"}):
        raw, report = module.migrate(home, "hyprland", connected)
    profile = tomllib.loads(raw.decode())
    assert report["outputs"] == 2, report
    assert profile["output"]["DP-1"] == {
        "mode": "1920x1080@400.002014", "position": [0, 1080],
        "scale": 1.0, "workspaces": [str(n) for n in range(1, 11)],
        "tearing": True, "direct_scanout": True}, profile["output"]
    assert report["workspace_home"] == "DP-1"
    assert profile["output"]["DP-3"]["vrr"] == "always"
    assert profile["output"]["DP-3"]["workspaces"] == "dynamic"
    assert profile["output"]["DP-3"]["tearing"] is True
    assert profile["output"]["DP-3"]["direct_scanout"] is True
    assert "vrr" not in profile["output"]["DP-1"]
    # Confirm VRR only when Umbriel reports a bool (false means supported but
    # disabled). A null on DP-3 is unsupported/unknown; its saved policy wins.
    from types import SimpleNamespace
    output_state = [
        {"name": "DP-1", "enabled": True, "scale": 1.0, "adaptive_sync": False},
        {"name": "DP-3", "enabled": True, "scale": 1.0, "adaptive_sync": None}
    ]
    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel"}), \
            patch.object(module.subprocess, "run",
                         return_value=SimpleNamespace(stdout=json.dumps(output_state))):
        live_raw, live_report = module.migrate(home, "hyprland", connected)
    live_profile = tomllib.loads(live_raw.decode())
    assert live_report["vrr_capable"] == ["DP-1"]
    assert live_profile["output"]["DP-1"]["vrr"] == "fullscreen"
    assert live_profile["output"]["DP-3"]["vrr"] == "always"
    # Explicit primary selection is independent of pointer/focus order and
    # remains stable when one named workspace is physically transferred.
    with patch.dict(os.environ, {"AWTARCHY_UMBRIEL_WORKSPACE_HOME": "DP-3"}):
        alternative, status = module.migrate(home, "hyprland", connected)
    different = tomllib.loads(alternative.decode())["output"]
    assert status["workspace_home"] == "DP-3"
    assert different["DP-3"]["workspaces"] == [str(n) for n in range(1, 11)]
    assert different["DP-1"]["workspaces"] == "dynamic"
    preference = home / ".config/umbriel/awtarchy-trial/workspace-home"
    preference.parent.mkdir(parents=True, exist_ok=True)
    preference.write_text("DP-1\\n".replace("\\n", "\n"))
    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel"}):
        repeat, persisted = module.migrate(home, "hyprland", connected)
    assert persisted["workspace_home"] == "DP-1"
    assert tomllib.loads(repeat.decode())["output"]["DP-1"]["workspaces"] == [
        str(n) for n in range(1, 11)]
    # Preserve a disconnected home preference rather than silently migrating
    # the 1-10 identities to a different display when the primary is unplugged.
    temporarily_absent, missing = module.migrate(home, "hyprland", {"DP-3"})
    assert missing["workspace_home"] == "DP-1"
    assert temporarily_absent
    keys = profile["keybinds"]
    assert keys["Super+F"] == "window-toggle-floating", keys
    assert keys["Super+Ctrl+F"] == "window-toggle-fullscreen"
    assert keys["Super+Q"] == "window-close"
    assert keys["Super+Alt+BackSpace"].endswith("quicksettings toggle")
    assert keys["Super+X"] == "scratchpad-toggle"
    assert keys["Alt+P"].endswith("launcher toggle")
    assert keys["Super+1"] == "workspace-switch --name 1"
    assert keys["Alt+Shift+1"] == "window-move-to-workspace --name 1"
    assert "Super+Alt+BracketLeft" not in keys  # Hyprland-only vibrance
    assert all("hyprctl" not in v and "swaymsg" not in v for v in keys.values())

    # Regression: Awtarchy's real default Hyprland window bindings are in
    # Lua arrays, not always standalone hl.bind calls. Import the supported
    # dispatcher actions without executing any Lua.
    hypr.write_text((ROOT / "config/hypr/hyprland.lua").read_text(encoding="utf-8"))
    current = module.hypr_bindings(home)
    assert current["Super+Q"] == "window-close", current
    assert current["Alt+F4"] == "window-close"
    assert current["Super+F"] == "window-toggle-floating"
    assert current["Super+Ctrl+F"] == "window-toggle-fullscreen"
    assert current["Alt+Tab"] == "window-focus-next"
    assert current["Super+Y"] == "window-toggle-pinned"
    assert current["Super+N"].endswith("notifications toggle")
    assert current["Alt+P"].endswith("launcher toggle")
    assert current["Alt+Shift+B"] == "spawn foot btop"
    assert current["Alt+V"] == "spawn foot wiremix"
    imported, _ = module.migrate(home, "hyprland", connected)
    overwritten = tomllib.loads(imported.decode()).get("keybinds", {})
    for chord in ("Alt+Shift+B", "Super+Shift+B", "Alt+V", "Super+V",
                  "Super+Alt+B", "Super+Ctrl+B", "Super+Alt+Ctrl+B"):
        assert chord not in overwritten, (chord, overwritten)

    # Restore the explicit-display fixture for subsequent migration checks.
    hypr.write_text(
        'hl.monitor({ output = "DP-1", mode = "1920x1080@400.002014", position = "0x1080", scale = 1, vrr = 0 })\n'
        'hl.monitor({ output = "DP-3", mode = "1920x1080@239.761002", position = "0x0", scale = 1, vrr = 1 })\n',
        encoding="utf-8")

    # A generated active hyprmoncfg override beats the Awtarchy root defaults.
    profile_path = home / ".config/hypr/hyprmoncfg-monitors.lua"
    profile_path.write_text(
        '-- Generated by hyprmoncfg\n'
        'hl.monitor({ output = "DP-1", mode = "1920x1080@360", position = "0x1080", scale = 1, vrr = 0 })\n'
        'hl.monitor({ output = "DP-3", mode = "1920x1080@240", position = "0x0", scale = 1, vrr = 0 })\n')
    raw, report = module.migrate(home, "hyprland", connected)
    assert tomllib.loads(raw.decode())["output"]["DP-1"]["mode"] == "1920x1080@360"
    profile_path.unlink()

    # A disconnected display must never receive imported configuration.
    raw, report = module.migrate(home, "hyprland", {"DP-3"})
    assert "DP-1" not in tomllib.loads(raw.decode())["output"]

    sway = home / ".config/sway/awtarchy-trial/config"
    sway.parent.mkdir(parents=True)
    sway.write_text(
        "bindsym Mod4+d exec bash $trial/ipc.sh launcher toggle\n"
        "bindsym Mod1+v exec python3 $trial/toggle-utility.py wiremix\n"
        "bindsym Mod4+f floating toggle\n"
        "bindsym Mod4+Control+f fullscreen toggle\n"
        "bindsym Mod1+1 workspace number 1\n"
        "bindsym Mod4+Shift+1 move container to workspace number 1\n"
        "bindsym Mod1+Left focus left\n"
        "bindsym Mod4+n exec bash $trial/ipc.sh notifications toggle\n"
        "bindsym Mod1+Tab exec python3 $trial/focus-cycle.py next\n")
    (sway.parent / "outputs").write_text(
        "output DP-1 mode 1920x1080@400.002014Hz position 0 1080 scale 1\n"
        "output DP-3 mode 1920x1080@239.761002Hz position 0 0 scale 1\n"
        "output DP-3 adaptive_sync on\n")
    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "sway"}):
        raw, report = module.migrate(home, connected=connected)
    profile = tomllib.loads(raw.decode())
    assert report["source"] == "sway"
    assert profile["output"]["DP-3"]["vrr"] == "always"
    assert profile["keybinds"]["Super+F"] == "window-toggle-floating"
    assert profile["keybinds"]["Super+Ctrl+F"] == "window-toggle-fullscreen"
    assert profile["keybinds"]["Super+D"].endswith("launcher toggle")
    assert profile["keybinds"]["Alt+1"] == "workspace-switch --name 1"
    assert "Alt+Tab" not in profile["keybinds"]  # Sway-specific focus-cycle utility

    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel"}):
        _, report = module.migrate(home, connected=connected)
    assert report["source"] == "hyprland" and "last use unknown" in report["selection"]
    marker = home / ".local/state/awtarchy/last-compositor"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("sway\n")
    with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel"}):
        _, report = module.migrate(home, connected=connected)
    assert report["source"] == "sway" and "recorded" in report["selection"]

    # Without active generated Lua, unambiguous saved hyprmoncfg JSON profiles
    # can still restore the user's exact monitor modes, positions and VRR.
    hypr.write_text('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", vrr = 0 })\n')
    prof_dir = home / ".config/hyprmoncfg/profiles"
    prof_dir.mkdir(parents=True)
    saved = {
        "name": "Gaming",
        "outputs": [
            {"name": "DP-1", "enabled": True, "mode": "1920x1080@400.002",
             "width": 1920, "height": 1080, "refresh": 400.002, "x": 0,
             "y": 1080, "scale": 1, "vrr": 0, "transform": 0},
            {"name": "DP-3", "enabled": True, "mode": "1920x1080@239.761",
             "width": 1920, "height": 1080, "refresh": 239.761, "x": 0,
             "y": 0, "scale": 1, "vrr": 2, "transform": 0},
        ],
    }
    (prof_dir / "gaming.json").write_text(json.dumps(saved))
    raw, report = module.migrate(home, "hyprland", connected)
    imported = tomllib.loads(raw.decode())["output"]
    assert imported["DP-1"]["mode"] == "1920x1080@400.002"
    assert imported["DP-3"]["vrr"] == "fullscreen"
    assert report["outputs"] == 2
    other = json.loads(json.dumps(saved))
    other["name"] = "Gaming 2"
    other["outputs"][0]["x"] = 1920
    (prof_dir / "other.json").write_text(json.dumps(other))
    raw, report = module.migrate(home, "hyprland", connected)
    assert report["outputs"] == 0, "Ambiguous monitor profiles must not be guessed"
    (prof_dir / "other.json").unlink()

    # No source script is executed, even when a malicious command is present.
    hypr.write_text('hl.bind("SUPER + N", hl.dsp.exec_cmd("rm -rf ~"), {})\n')
    raw, report = module.migrate(home, "hyprland", connected)
    assert "rm -rf" not in raw.decode()

print("PASS: source-selective Umbriel display and keybind migration, no source execution")
