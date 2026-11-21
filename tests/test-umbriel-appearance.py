#!/usr/bin/env python3
"""Umbriel decoration/theme, flyout ownership, and display UI regressions."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile
import tomllib
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
UMBRIEL = ROOT / "compositors/umbriel"
SWAY = ROOT / "compositors/sway"
config = tomllib.loads((UMBRIEL / "config.toml").read_text())
native = tomllib.loads((UMBRIEL / "native-config.toml").read_text())
assert config["appearance"]["border_width"] == 1
assert config["appearance"]["corner_radius"] == 0
assert config["appearance"]["outer_border_width"] == 0
assert config["animation"]["windows_in"]["style"] == "popin"
assert config["animation"]["windows_in"]["scale"] == .87
assert config["animation"]["workspaces"]["enabled"] is False
assert config["animation"]["layers"]["enabled"] is True
assert config["keybinds"]["Super+Ctrl+M"] == "spawn wdisplays"
assert "wdisplays" in (UMBRIEL / "manage.sh").read_text()
assert "awtarchy-trial/theme.toml" in native["include"]["files"]
assert native["include"]["files"].index("awtarchy-trial/theme.toml") < (
    native["include"]["files"].index("awtarchy-trial/migrated.toml"))
subprocess.run(["bash", "-n", str(UMBRIEL / "theme-apply.sh")], check=True)

spec = importlib.util.spec_from_file_location("umbriel_theme", UMBRIEL / "theme-colors.py")
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)
with tempfile.TemporaryDirectory(prefix="umbriel-theme-test-") as temporary:
    home = Path(temporary)
    themes = home / ".config/hypr/themes"
    themes.mkdir(parents=True)
    (themes / "steel").write_text(
        "NEW_ACTIVE_BORDER = '2a55ccff'\n"
        "NEW_INACTIVE_BORDER = '3b3b3bff'\n"
        "QS_BACKGROUND = '#111111'\n"
        "QS_FOREGROUND = '#eeeeee'\n"
        "QS_FOCUS = '#424242'\n",
        encoding="utf-8")
    (themes / "catppuccin-frappé").write_text(
        "NEW_ACTIVE_BORDER=aabbccff\nNEW_INACTIVE_BORDER=223344ff\n")
    assert theme.palette(home, "catppuccin-frappé")["active_border"] == "aabbccff"
    selected = theme.palette(home, "steel")
    rendered = theme.render_toml(selected)
    loaded = tomllib.loads(rendered.decode())
    assert loaded["colors"]["border"]["focused"] == "#2A55CCFF"
    assert loaded["colors"]["border"]["unfocused"] == "#3B3B3BFF"
    assert loaded["colors"]["background"] == "#111111FF"
    assert loaded["colors"]["text_primary"] == "#EEEEEEFF"
    assert theme.quickshell_palette(selected).decode().count("#424242") == 1
    theme.save_theme(home, "steel")
    assert (home / ".config/umbriel/awtarchy-trial/theme.toml").read_bytes() == rendered
    assert (home / ".local/state/awtarchy/active-theme-umbriel").read_text() == "steel\n"
    for invalid in ("../steel", ".", "foo/bar", "steel\nbad"):
        try:
            theme.palette(home, invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Accepted unsafe theme name: " + repr(invalid))
    (themes / "broken").write_text("NEW_ACTIVE_BORDER=nothex\n")
    try:
        theme.palette(home, "broken")
    except ValueError:
        pass
    else:
        raise AssertionError("Accepted malformed border color")
    # Rendering an Umbriel-only theme must never create or edit Hyprland or
    # Sway compositor configuration files.
    assert not (home / ".config/hypr/hyprland.lua").exists()
    assert not (home / ".config/sway/config").exists()

    rendered_dir = home / "rendered"
    subprocess.run([
        sys.executable, str(UMBRIEL / "render-quickshell.py"),
        "--repo", str(ROOT), "--dest", str(rendered_dir)
    ], check=True, timeout=85)
    owner = (rendered_dir / "FlyoutManager.qml").read_text()
    assert "closeRequested(surface);" in owner
    assert "closeRequested(key);" in owner
    assert "hyprEventConnection" not in owner
    assert 'activeSurface = surface;' in owner
    picker = (rendered_dir / "ThemePicker.qml").read_text()
    assert "onCloseRequested(exceptSurface)" in picker
    assert "/umbriel/awtarchy-trial/theme-apply.sh" in picker
    assert "active-theme-umbriel" in picker
    assert "/sway/awtarchy-trial/" not in picker
    assert "/hypr/scripts/quickshell_theme_apply.sh" not in picker
    theme_qml = (rendered_dir / "Theme.qml").read_text()
    assert "/quickshell/awtarchy-umbriel/theme.json" in theme_qml
    flyout = (rendered_dir / "UmbrielFlyoutWindow.qml").read_text()
    assert "popup.dragFromRight ? -1 : 1" in flyout
    assert "popup.dragFromBottom ? -1 : 1" in flyout
    assert "popup.resizeCommitted(popup.resizePreviewWidth," in flyout
    # Umbriel's experiment must show the resized surface as the drag moves,
    # rather than Sway's deferred dimensions overlay.
    assert "visible: swayResizeDrag.active" not in flyout
    assert "popup.implicitWidth = popup.resizePreviewWidth" not in flyout

    # Sway has the same single-flyout ownership correction, with no changes
    # to the upstream Hyprland shell.
    sway_dir = home / "sway-rendered"
    subprocess.run([
        sys.executable, str(SWAY / "render-quickshell.py"),
        "--source", str(ROOT / "config/quickshell/awtarchy"),
        "--dest", str(sway_dir), "--bridge-dir", str(SWAY)
    ], check=True, timeout=85)
    assert "closeRequested(surface);" in (sway_dir / "FlyoutManager.qml").read_text()
    assert "closeRequested(surface);" not in (
        ROOT / "config/quickshell/awtarchy/FlyoutManager.qml").read_text()

print("PASS: Umbriel square border/animation settings, native theme and single-flyout routing")
