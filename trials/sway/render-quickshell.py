#!/usr/bin/env python3
"""Generate an isolated Sway profile from Awtarchy's current Hyprland UI source.

This does not modify or symlink the existing shell. Scripts that need native
Sway IPC must be implemented separately and reviewed before a live trial.
"""
import argparse
from pathlib import Path
import re
import shutil
import sys

BRIDGE_FILES = ("SwayBridge.qml", "SwayFocusGrab.qml", "ScreenShareGuardCard.qml")
# The shared Awtarchy UI has per-flyout capture exclusion controls.
# Sway does not provide a verified equivalent to Hyprland's capture rules.
# Never advertise those controls as effective, or corrupt shared Hyprland
# capture preferences while a Sway user saves other appearance settings.
CAPTURE_SURFACES = {
    "Launcher.qml": "launcher",
    "ClipboardMenu.qml": "clipboard",
    "Notifications.qml": "notifications",
    "NetworkMenu.qml": "network",
    "QuickSettings.qml": "quick_settings",
    "BluetoothMenu.qml": "bluetooth",
    "BatteryMenu.qml": "battery",
}

def disable_unavailable_capture_controls(text: str, surface: str) -> str:
    expr = (
        r'readonly property bool captureAllowed: captureAllowedOverride >= 0'
        r'\n[ \t]*\? captureAllowedOverride === 1 : '
        r'BarState\.captureAllowedFor\("' + re.escape(surface) + r'"\)'
    )
    text, replaced = re.subn(expr, 'readonly property bool captureAllowed: true', text)
    if replaced != 1:
        raise ValueError("Capture state changed in " + surface + "; refusing unsafe UI rewrite")
    fn = re.compile(
        r'(?m)^    function toggleCaptureAllowed\(\) \{.*?^    \}',
        flags=re.DOTALL
    )
    replacement = (
        '    function toggleCaptureAllowed() {\n'
        '        settingsMessage = "Sway: capture exclusion is unavailable; '
        'this surface is visible in screen shares.";\n'
        '    }'
    )
    text, replaced = fn.subn(lambda _: replacement, text)
    if replaced != 1:
        raise ValueError("Capture toggle changed in " + surface + "; refusing unsafe UI rewrite")
    # Keep the user's Hyprland privacy preferences unchanged when saving
    # otherwise compatible flyout/launcher visual options from Sway.
    capture_arg = 'captureAllowed ? "true" : "false"'
    if text.count(capture_arg) != 1:
        raise ValueError("Capture save argument changed in " + surface)
    text = text.replace(
        capture_arg,
        'BarState.captureAllowedFor("' + surface + '") ? "true" : "false"'
    )
    return text

TRANSLATIONS = {
    "/hypr/scripts/quickshell.sh": "/sway/awtarchy-trial/quickshell.sh",
    "/hypr/scripts/quickshell_runtime_rules.sh": "/sway/awtarchy-trial/runtime-rules.sh",
    "/hypr/scripts/quickshell_launcher_position.sh": "/sway/awtarchy-trial/position.sh",
    "/hypr/scripts/quickshell_flyout_position.sh": "/sway/awtarchy-trial/position.sh",
    "/hypr/scripts/quickshell_flyout_prepare.sh": "/sway/awtarchy-trial/position.sh",
    "/hypr/scripts/hypr_quicksettings.sh": "/sway/awtarchy-trial/quicksettings.sh",
    "/hypr/scripts/quickshell_application_state.sh": "/sway/awtarchy-trial/application-state.sh",
    "/hypr/scripts/quickshell_sensitive_capture.sh": "/sway/awtarchy-trial/sensitive-capture.sh",
    "/hypr/scripts/quickshell_bar_drag_runtime.sh": "/sway/awtarchy-trial/runtime-rules.sh",
}

def render(source: Path, destination: Path, trial: Path):
    if not source.is_dir() or source.is_symlink():
        raise ValueError("Unsafe Quickshell source")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Sway Quickshell destination already exists")
    candidates = sorted(source.iterdir())
    if not candidates or not any(p.name == "shell.qml" for p in candidates):
        raise ValueError("Quickshell source missing shell.qml")
    if any(p.is_symlink() or not p.is_file() for p in candidates):
        raise ValueError("Refusing unexpected Quickshell source entry")
    if any(not (trial / name).is_file() or (trial / name).is_symlink() for name in BRIDGE_FILES):
        raise ValueError("Missing Sway Wayland QML bridge")
    destination.mkdir(parents=True)
    try:
        for path in candidates:
            # Sway has no verified dynamic capture-shield API. Never allow the
            # Hyprland capture toggle to misrepresent protection.
            if path.name == "ScreenShareGuardCard.qml":
                shutil.copyfile(trial / path.name, destination / path.name)
                continue
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".qml":
                text = text.replace("import Quickshell.Hyprland\n", "import Quickshell.Wayland\n")
                text = text.replace("HyprlandFocusGrab", "SwayFocusGrab")
                text = re.sub(r"\bHyprland\b", "SwayBridge", text)
                if path.name in CAPTURE_SURFACES:
                    text = disable_unavailable_capture_controls(
                        text, CAPTURE_SURFACES[path.name])
                for old, new in TRANSLATIONS.items():
                    text = text.replace(old, new)
                if path.name == "shell.qml":
                    text = text.replace("//@ pragma ShellId awtarchy", "//@ pragma ShellId awtarchy-sway")
                    text = text.replace("awtarchy-quickshell", "awtarchy-sway-quickshell")
                if path.name == "Bar.qml":
                    text = text.replace(
                        'onRightClicked: Quickshell.execDetached([bar.wiremixScript])',
                        'onRightClicked: SwayBridge.toggleUtility("Wiremix", '
                        '["foot", "--app-id", "Wiremix", "--title", "Wiremix", '
                        '"wiremix", "-p", "auto", "-f", "30"])')
                    text = text.replace(
                        'readonly property string wiremixScript: configHome + "/hypr/scripts/wiremix-toggle.sh"\n',
                        '')
                    text = text.replace(
                        '/hypr/scripts/toggle_mouse_submap.sh',
                        '/sway/awtarchy-trial/mode-help.sh')
                    text = text.replace(
                        'tooltip: "Toggle mouse submap"',
                        'tooltip: "Sway: press SUPER+ALT+M to toggle mouse mode"')
                    text = text.replace(
                        'tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"',
                        'tooltip: "Sway mode: " + submapFile.text().trim() + " (press SUPER+ALT+N/M/V to toggle)"')
                    text = text.replace(
                        '[bar.mouseSubmapScript, "reset"]',
                        '[bar.mouseSubmapScript, "help"]')
                    text = text.replace(
                        '[bar.mouseSubmapScript, "toggle"]',
                        '[bar.mouseSubmapScript, "help"]')
                    text = text.replace(
                        'Quickshell.env("HYPR_SUBMAP_STATE_FILE") || (runtimeHome + "/awtarchy-hypr-submap")',
                        '(runtimeHome + "/awtarchy-sway-submap")')
                    start = text.index("    function focusWorkspace(selector) {")
                    end = text.index("\n    }", start) + len("\n    }")
                    text = text[:start] + """    function focusWorkspace(selector) {
        SwayBridge.activateWorkspace(selector);
    }""" + text[end:]
                    # Sway provides workspace-manager Wayland operations; no
                    # false "move window" substitution for whole workspace.
                    text = re.sub(
                        r'Quickshell\.execDetached\(\["hyprctl", "eval", "hl\.dispatch\(hl\.dsp\.workspace\.move\(\{ monitor = \\"" \+ (\w+)\.modelData\.dir \+ "\\" \}\)\)"\]\)',
                        r'SwayBridge.moveWorkspace(\1.modelData.dir)', text)
                if path.name == "shell.qml":
                    text = text.replace(
                        'function ping(): string { return "ok"; }',
                        'function ping(): string { return "ok"; }\n'
                        '        function toggleDefaultApps(): void {\n'
                        '            SwayBridge.toggleUtility("awtarchy-default-apps", '
                        '["foot", "--app-id", "awtarchy-default-apps", '
                        '"--title", "awtarchy-default-apps", "python3", '
                        '(Quickshell.env("XDG_CONFIG_HOME") || '
                        '(Quickshell.env("HOME") + "/.config")) '
                        '+ "/hypr/scripts/default_applications.py", "tui"]);\n'
                        '        }')
                if path.name == "KeyboardLockState.qml":
                    text = text.replace(
                        '["hyprctl", "devices", "-j"]',
                        '["python3", (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/sway/awtarchy-trial/keyboard-state.py"]')
                if path.name == "NumlockSessionTweak.qml":
                    # Sway does not have a verified equivalent to Hyprland's
                    # numlock_by_default mutation. Do not run synthetic commands
                    # or imply that a saved preference was actually applied.
                    text = """pragma Singleton
import QtQuick
import Quickshell as Qs
Qs.Singleton {
    readonly property bool enabled: false
    function enforce() { return false; }
}
"""
                    (destination / path.name).write_text(text, encoding="utf-8")
                    continue
                if path.name == "FlyoutSettings.qml":
                    # This shared panel has a *second* independent capture
                    # writer for Network and Bluetooth. Remove it in Sway.
                    raw = 'readonly property bool effectiveShowCaptureControl: showCaptureControl\n        || managedConnectivityCapture'
                    if raw not in text:
                        raise ValueError("FlyoutSettings capture controls changed")
                    text = text.replace(
                        raw,
                        'readonly property bool effectiveShowCaptureControl: false')
                    start = text.index('    function toggleCaptureControl() {')
                    end = text.index('\n    }', start) + len('\n    }')
                    text = text[:start] + (
                        '    function toggleCaptureControl() {\n'
                        '        managedMessage = "Sway does not support per-window capture exclusion.";\n'
                        '    }') + text[end:]
                if path.name == "CaptureEyeButton.qml":
                    # The shared eye icon must never accept clicks that
                    # pretend Sway can exclude surfaces from screencopy.
                    if 'enabled: !root.locked' not in text:
                        raise ValueError("CaptureEyeButton changed")
                    text = text.replace('enabled: !root.locked', 'enabled: false')
                if path.name == "QuickSettings.qml":
                    text = text.replace(
                        '/hypr/scripts/default_applications.sh',
                        '/sway/awtarchy-trial/default-apps.sh')
                    # Preserve supported bar + audio state. Do not offer
                    # nonfunctional night-light, vibrance or input-mode toggles.
                    text = text.replace(
                        'visible: root.quickSettingsSectionVisible("display-effects")',
                        'visible: false')
                    text = text.replace(
                        'visible: root.quickSettingsSectionVisible("submap")',
                        'visible: false')
                    text = text.replace(
                        'visible: root.quickSettingsSectionVisible("numlock")',
                        'visible: false')
                    text = text.replace(
                        'text: "SwayBridge Submap"',
                        'text: "Sway input modes (keyboard shortcuts)"')
                if path.name == "PowerMenu.qml":
                    text = text.replace(
                        "/hypr/scripts/awtarchy_lock.sh",
                        "/sway/awtarchy-trial/lock.sh")
                    # Sway's lock.sh itself waits for a secure Quickshell lock
                    # or returns only after swaylock -f confirms locking.
                    # Do not make fallback success depend on Quickshell IPC.
                    text = text.replace(
                        " && ~/.config/sway/awtarchy-trial/lock.sh wait-secure 5", "")
                    text = text.replace(
                        "/hypr/scripts/quickshell_lockscreen_capture.sh",
                        "/sway/awtarchy-trial/lock-capture.sh")
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
        print(f"Sway render failed: {exc}", file=sys.stderr)
        sys.exit(1)
