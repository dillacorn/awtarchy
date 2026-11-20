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
    bridge_dir = root / "trials/umbriel"
    sway_renderer = root / "trials/sway/render-quickshell.py"
    if destination.exists() or destination.is_symlink():
        raise ValueError("Refusing to replace existing Umbriel shell")
    spec = importlib.util.spec_from_file_location("awtarchy_sway_renderer", sway_renderer)
    sway = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sway)
    with tempfile.TemporaryDirectory(prefix="awtarchy-umbriel-qs-") as temp:
        stage = Path(temp) / "awtarchy-sway"
        sway.render(root / "config/quickshell/awtarchy", stage, root / "trials/sway")
        result = Path(temp) / "awtarchy-umbriel"
        result.mkdir()
        for source in sorted(stage.iterdir()):
            if not source.is_file() or source.is_symlink():
                raise ValueError("Unexpected generated Sway shell asset")
            target = RENAME.get(source.name, source.name)
            if source.name == "SwayBridge.qml":
                text = (bridge_dir / "UmbrielBridge.qml").read_text(encoding="utf-8")
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
                    text = text.replace("Sway", "Umbriel")
                    if source.name == "Bar.qml":
                        old = "        UmbrielBridge.activateWorkspace(selector);"
                        new = "        UmbrielBridge.activateWorkspace(selector, monitorName);"
                        if text.count(old) != 1:
                            raise ValueError("Umbriel bar workspace target changed")
                        text = text.replace(old, new, 1)
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
