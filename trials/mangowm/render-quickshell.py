#!/usr/bin/env python3
"""Render an isolated Mango Quickshell profile from a pinned Awtarchy source tree.

Used on a temporary updater target root or through trial setup, never in-place
on the user's existing Hyprland Quickshell files.
"""
import argparse
from pathlib import Path
import re
import shutil
import sys

def render(source: Path, dest: Path, bridge_dir: Path):
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Unsafe Awtarchy Quickshell source")
    if dest.exists() or dest.is_symlink():
        raise ValueError("Mango shell destination already exists")
    source_files = sorted(source.iterdir())
    if not source_files or not any(p.name == "shell.qml" for p in source_files):
        raise ValueError("Missing Quickshell shell.qml")
    if any(p.is_symlink() or not p.is_file() for p in source_files):
        raise ValueError("Unexpected Quickshell source item")
    if not all((bridge_dir / x).is_file() and not (bridge_dir / x).is_symlink()
               for x in ("MangoBridge.qml", "MangoFocusGrab.qml")):
        raise ValueError("Missing Mango Quickshell adapter")

    dest.mkdir(parents=True)
    try:
        for file in source_files:
            text = file.read_text(encoding="utf-8")
            if file.suffix == ".qml":
                text = text.replace("import Quickshell.Hyprland\n",
                                    "import Quickshell.Wayland\n")
                text = re.sub(r"\bHyprlandFocusGrab\b",
                              "MangoFocusGrab", text)
                text = re.sub(r"\bHyprland\b", "MangoBridge", text)
                if file.name == "shell.qml":
                    text = text.replace("//@ pragma ShellId awtarchy",
                                        "//@ pragma ShellId awtarchy-mango")
                    text = text.replace("awtarchy-quickshell",
                                        "awtarchy-mango-quickshell")
                    text = text.replace(
                        'configHome + "/hypr/scripts/quickshell.sh"',
                        'configHome + "/mango/scripts/quickshell.sh"')
                    text = text.replace(
                        'configHome + "/hypr/scripts/quickshell_runtime_rules.sh"',
                        'configHome + "/mango/scripts/runtime-rules.sh"')
                if file.name == "KeyboardLockState.qml":
                    # Mango does not expose Hyprland's capslock device event.
                    # Use the kernel LED state as a best-effort fallback.
                    text = text.replace('["hyprctl", "devices", "-j"]',
                                        '["python3", (Quickshell.env("XDG_CONFIG_HOME") || ' +
                                        '(Quickshell.env("HOME") + "/.config")) ' +
                                        '+ "/mango/scripts/keyboard-state.py"]')
                if file.name == "Bar.qml":
                    # A tag is not a Hyprland workspace. Rebind only the
                    # identical view operations; do not translate workspace
                    # moves into a different (window move) dispatcher.
                    start = text.index("    function focusWorkspace(selector) {")
                    stop = text.index("    }", start) + len("    }")
                    text = text[:start] + '''    function focusWorkspace(selector) {
        const action = selector === "e-1" ? "viewtoleft"
            : selector === "e+1" ? "viewtoright" : "view," + selector;
        Quickshell.execDetached(["mmsg", "dispatch", action]);
    }''' + text[stop:]
                    for slot in ("arrowSlot", "arrowSlotVertical"):
                        matches = [line for line in text.splitlines()
                                   if "onClicked: Quickshell.execDetached" in line
                                   and "hyprctl" in line
                                   and slot + ".modelData.dir" in line]
                        if len(matches) != 1:
                            raise ValueError("Mango unsupported monitor arrow action")
                        # Deliberately leave workspace-transfer UI disabled,
                        # instead of moving a single window as a fake match.
                        text = text.replace(matches[0],
                            matches[0].split("onClicked:")[0] +
                            'enabled: false // Mango has no equivalent to move whole workspace')
                if '"hyprctl"' in text or "hl.dispatch(" in text:
                    raise ValueError("Unported direct Hyprland QML dispatch in " + file.name)
                text = text.replace('text: "MangoBridge Submap"',
                                    'text: "Mango Key Mode"')
            (dest / file.name).write_text(text, encoding="utf-8")
        for file in ("MangoBridge.qml", "MangoFocusGrab.qml"):
            shutil.copyfile(bridge_dir / file, dest / file)
    except Exception:
        shutil.rmtree(dest)
        raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--dest", type=Path, required=True)
    parser.add_argument("--bridge-dir", type=Path, required=True)
    opts = parser.parse_args()
    try:
        render(opts.source, opts.dest, opts.bridge_dir)
    except (ValueError, OSError, UnicodeError) as exc:
        print(f"Mango Quickshell migration failed: {exc}", file=sys.stderr)
        sys.exit(1)
