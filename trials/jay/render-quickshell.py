#!/usr/bin/env python3
"""Generate an isolated Jay profile from Awtarchy's current Hyprland UI source.

This does not modify or symlink the existing shell. Scripts that need native
Jay IPC must be implemented separately and reviewed before a live trial.
"""
import argparse
from pathlib import Path
import re
import shutil
import sys

BRIDGE_FILES = ("JayBridge.qml", "JayFocusGrab.qml")
TRANSLATIONS = {
    "/hypr/scripts/quickshell.sh": "/jay/awtarchy-trial/quickshell.sh",
    "/hypr/scripts/quickshell_runtime_rules.sh": "/jay/awtarchy-trial/runtime-rules.sh",
    "/hypr/scripts/quickshell_launcher_position.sh": "/jay/awtarchy-trial/position.sh",
    "/hypr/scripts/quickshell_flyout_position.sh": "/jay/awtarchy-trial/position.sh",
    "/hypr/scripts/quickshell_flyout_prepare.sh": "/jay/awtarchy-trial/position.sh",
    "/hypr/scripts/hypr_quicksettings.sh": "/jay/awtarchy-trial/quicksettings.sh",
    "/hypr/scripts/quickshell_application_state.sh": "/jay/awtarchy-trial/application-state.sh",
}

def render(source: Path, destination: Path, trial: Path):
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Unsafe Quickshell source")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Jay Quickshell destination already exists")
    candidates = sorted(source.iterdir())
    if not candidates or not any(p.name == "shell.qml" for p in candidates):
        raise ValueError("Quickshell source missing shell.qml")
    if any(p.is_symlink() or not p.is_file() for p in candidates):
        raise ValueError("Refusing unexpected Quickshell source entry")
    if any(not (trial / name).is_file() or (trial / name).is_symlink() for name in BRIDGE_FILES):
        raise ValueError("Missing Jay Wayland QML bridge")
    destination.mkdir(parents=True)
    try:
        for path in candidates:
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".qml":
                text = text.replace("import Quickshell.Hyprland\n", "import Quickshell.Wayland\n")
                text = text.replace("HyprlandFocusGrab", "JayFocusGrab")
                text = re.sub(r"\bHyprland\b", "JayBridge", text)
                for old, new in TRANSLATIONS.items():
                    text = text.replace(old, new)
                if path.name == "shell.qml":
                    text = text.replace("//@ pragma ShellId awtarchy", "//@ pragma ShellId awtarchy-jay")
                    text = text.replace("awtarchy-quickshell", "awtarchy-jay-quickshell")
                if path.name == "Bar.qml":
                    start = text.index("    function focusWorkspace(selector) {")
                    end = text.index("\n    }", start) + len("\n    }")
                    text = text[:start] + """    function focusWorkspace(selector) {
        JayBridge.activateWorkspace(selector);
    }""" + text[end:]
                    # Jay provides workspace-manager Wayland operations; no
                    # false "move window" substitution for whole workspace.
                    text = re.sub(
                        r'Quickshell\.execDetached\(\["hyprctl", "eval", "hl\.dispatch\(hl\.dsp\.workspace\.move\(\{ monitor = \\"" \+ (\w+)\.modelData\.dir \+ "\\" \}\)\)"\]\)',
                        r'JayBridge.moveWorkspace(\1.modelData.dir)', text)
                if path.name == "NumlockSessionTweak.qml":
                    # No verified Jay numlock configuration command. Do not
                    # execute the Hyprland dispatcher in the other session.
                    text = text.replace('"hyprctl", "eval",', '"false",')
                    text = text.replace('"hl.config({ input = { numlock_by_default = true } })"', '""')
                    text = text.replace('"hl.config({ input = { numlock_by_default = false } })"', '""')
                if '"hyprctl"' in text or "hl.dispatch(" in text:
                    raise ValueError("Unported Hyprland QML dispatch: " + path.name)
            (destination / path.name).write_text(text, encoding="utf-8")
        for name in BRIDGE_FILES:
            shutil.copyfile(trial / name, destination / name)
    except Exception:
        shutil.rmtree(destination)
        raise

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--dest", type=Path, required=True)
    p.add_argument("--bridge-dir", type=Path, required=True)
    opts = p.parse_args()
    try:
        render(opts.source, opts.dest, opts.bridge_dir)
    except (ValueError, OSError, UnicodeError) as exc:
        print(f"Jay render failed: {exc}", file=sys.stderr)
        sys.exit(1)
