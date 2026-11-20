#!/usr/bin/env python3
"""Render the actual Awtarchy Quickshell UI for an isolated Umbriel session.

Reuse the maintained Sway layer-shell conversion, then substitute only the
Umbriel compositor bridge. Hyprland and Sway source/config files are read-only.
The shell is EXPERIMENTAL: compositor-specific operations need live verification.
"""
import argparse
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile

RENAME = {
    "SwayBridge.qml": "UmbrielBridge.qml",
    "SwayFocusGrab.qml": "UmbrielFocusGrab.qml",
    "SwayDragBridge.qml": "UmbrielDragBridge.qml",
    "SwayFlyoutWindow.qml": "UmbrielFlyoutWindow.qml",
}


def render(repo: Path, destination: Path):
    root = repo.resolve()
    bridge_dir = root / "compositors/umbriel"
    sway_renderer = root / "compositors/sway/render-quickshell.py"
    if destination.exists() or destination.is_symlink():
        raise ValueError("Refusing to replace existing Umbriel shell")
    spec = importlib.util.spec_from_file_location("awtarchy_sway_renderer", sway_renderer)
    sway = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sway)
    with tempfile.TemporaryDirectory(prefix="awtarchy-umbriel-qs-") as temp:
        stage = Path(temp) / "awtarchy-sway"
        sway.render(root / "config/quickshell/awtarchy", stage, root / "compositors/sway")
        result = Path(temp) / "awtarchy-umbriel"
        result.mkdir()
        for source in sorted(stage.iterdir()):
            if not source.is_file() or source.is_symlink():
                raise ValueError("Unexpected generated Sway shell asset")
            target = RENAME.get(source.name, source.name)
            if source.name == "SwayBridge.qml":
                text = (bridge_dir / "UmbrielBridge.qml").read_text(encoding="utf-8")
            elif source.name == "ScreenSharePicker.qml":
                text = (bridge_dir / "ScreenSharePicker.qml").read_text(encoding="utf-8")
            elif source.name == "TitleBarsCard.qml":
                text = (bridge_dir / "TitleBarsCard.qml").read_text(encoding="utf-8")
            elif source.name == "ScreenShareGuardCard.qml":
                # Sway's static unavailable card is incorrect: Umbriel provides
                # genuine block_capture window rules and has its own backend.
                text = (root / "config/quickshell/awtarchy"
                        / "ScreenShareGuardCard.qml").read_text(encoding="utf-8")
                before = "/hypr/scripts/screenshare_guard.sh"
                if text.count(before) != 1:
                    raise ValueError("Source Screen Share Guard path changed")
                text = text.replace(before,
                    "/umbriel/awtarchy-trial/screenshare-guard.sh")
            else:
                try:
                    text = source.read_text(encoding="utf-8")
                except UnicodeError:
                    shutil.copyfile(source, result / target)
                    continue
                if source.suffix == ".qml":
                    text = text.replace("SwayBridge", "UmbrielBridge")
                    text = text.replace("SwayFocusGrab", "UmbrielFocusGrab")
                    text = text.replace("SwayDragBridge", "UmbrielDragBridge")
                    text = text.replace("SwayFlyoutWindow", "UmbrielFlyoutWindow")
                    text = text.replace("/sway/awtarchy-trial/", "/umbriel/awtarchy-trial/")
                    text = text.replace("/quickshell/awtarchy-sway/", "/quickshell/awtarchy-umbriel/")
                    text = text.replace("awtarchy-sway", "awtarchy-umbriel")
                    text = text.replace("active-theme-sway", "active-theme-umbriel")
                    text = text.replace("Sway", "Umbriel")
                    if source.name == "Bar.qml":
                        # Unlike Sway, native Umbriel uses Super as its drag
                        # modifier. Do not display Sway's Alt-only instruction.
                        text = text.replace(
                            "Toggle Umbriel mouse mode (Alt still required to drag/resize)",
                            "Toggle Umbriel mouse mode (Super+drag/resize)")
                        text = text.replace(
                            "/umbriel/awtarchy-trial/mode-control.sh",
                            "/umbriel/awtarchy-trial/mode-control.py")
                        # Umbriel has one active workspace on EACH output; focused
                        # is true only on the keyboard-focused output. A hidden
                        # empty active workspace would make the bar appear stuck.
                        old_visible = ("return workspace.focused || workspace.active "
                                       "|| workspace.toplevels.values.length > 0;")
                        if text.count(old_visible) != 1:
                            raise ValueError("Umbriel workspace visibility predicate changed")
                        text = text.replace(
                            old_visible,
                            "return workspace.active || workspace.toplevels.values.length > 0;",
                            1)
                        old_selected = ("modelData.focused ? Theme.subtleActive "
                                        ': "transparent"')
                        selected_count = text.count(old_selected)
                        if selected_count < 2:
                            raise ValueError("Umbriel workspace selection highlights changed")
                        text = text.replace(
                            old_selected,
                            'modelData.active ? Theme.subtleActive : "transparent"')
                        old = "        UmbrielBridge.activateWorkspace(selector);"
                        new = "        UmbrielBridge.activateWorkspace(selector, monitorName);"
                        if text.count(old) != 1:
                            raise ValueError("Umbriel bar workspace target changed")
                        text = text.replace(old, new, 1)
                    if source.name == "FloatingWindowsState.qml":
                        source_helper = "/hypr/scripts/quickshell_floating_windows.sh"
                        if text.count(source_helper) != 1:
                            raise ValueError("Umbriel global floating source helper changed")
                        text = text.replace(source_helper,
                            "/umbriel/awtarchy-trial/floating-windows.sh")
                        original_state = "/awtarchy-floating-windows-state"
                        if text.count(original_state) != 1:
                            raise ValueError("Umbriel global floating state path changed")
                        text = text.replace(original_state,
                            "/awtarchy-umbriel-floating-windows-state")
                    if source.name == "ScreenshotSoundSettings.qml":
                        # Both the inherited Sway and Hyprland preference paths
                        # must read the same shared file during an Umbriel login.
                        text = text.replace(
                            "/hypr/scripts/screenshot_sound.sh",
                            "/umbriel/awtarchy-trial/screenshot_sound.sh")
                    if "swaymsg " in text or "hyprctl " in text or "import Quickshell.I3" in text:
                        raise ValueError("Unported compositor-specific QML: " + source.name)
            (result / target).write_text(text, encoding="utf-8")
        if not (result / "UmbrielBridge.qml").is_file():
            raise ValueError("Umbriel bridge not generated")
        shutil.copytree(result, destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--dest", type=Path, required=True)
    args = parser.parse_args()
    try:
        render(args.repo, args.dest)
    except (OSError, ValueError, UnicodeError) as exc:
        print("Umbriel Quickshell render: " + str(exc), file=sys.stderr)
        sys.exit(1)
