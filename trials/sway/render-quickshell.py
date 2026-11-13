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

BRIDGE_FILES = ("SwayBridge.qml", "SwayFocusGrab.qml", "ScreenShareGuardCard.qml", "SwayDragBridge.qml", "SwayFlyoutWindow.qml")
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

# These seven modules declare regular application toplevels in the Hyprland
# source. The Sway render uses native layer-shell panels instead so no Sway
# workspace ever sees an intermediate tiled window.
SWAY_LAYER_FLYOUTS = {
    "Launcher.qml": ("launcherWindow", "launcher", "requestedPlacement"),
    "ClipboardMenu.qml": ("clipboardWindow", "clipboard", "placement"),
    "Notifications.qml": ("centerWindow", "notifications", "placement"),
    "QuickSettings.qml": ("quickSettingsWindow", "quick-settings", "placement"),
    "NetworkMenu.qml": ("networkWindow", "network", "placement"),
    "BluetoothMenu.qml": ("bluetoothWindow", "bluetooth", "placement"),
    "BatteryMenu.qml": ("batteryWindow", "battery", "placement"),
}


def render_layer_flyout(text: str, filename: str) -> str:
    window_id, role, placement = SWAY_LAYER_FLYOUTS[filename]
    source = f'    FloatingWindow {{\\n        id: {window_id}\\n'
    target = (
        f'    SwayFlyoutWindow {{\\n'
        f'        id: {window_id}\\n'
        f'        surfaceRole: "{role}"\\n'
        f'        placement: root.{placement}\\n'
    )
    # Use actual newlines above: escaping in a code-generation helper is
    # intentional, but the generated content remains ordinary QML.
    source = source.replace('\\n', '\n')
    target = target.replace('\\n', '\n')
    if filename == "Notifications.qml":
        target += "        edgeAnchor: root.anchorAlongEdge\\n".replace('\\n', '\n')
    if text.count(source) != 1:
        raise ValueError(f"Missing exact Sway flyout window: {filename}:{window_id}")
    if text.count("FloatingWindow {") != 1:
        raise ValueError(f"Unexpected extra toplevel windows in {filename}")
    return text.replace(source, target, 1)


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
    "/hypr/scripts/quickshell_theme_apply.sh": "/sway/awtarchy-trial/theme-apply.sh",
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
                if path.name in SWAY_LAYER_FLYOUTS:
                    text = render_layer_flyout(text, path.name)
                    # Sway layer-shell positions belong to the target output.
                    # The Hyprland source keeps mapped windows on their old
                    # screen and moves them by compositor IPC. That no-op
                    # positioning path is wrong for a Sway PanelWindow, so
                    # explicitly remap on a cross-monitor handoff instead.
                    window_id, _, _ = SWAY_LAYER_FLYOUTS[path.name]
                    target_name = "target" if path.name == "ClipboardMenu.qml" else "targetScreen"
                    old_screen = (f"        if (!{window_id}.visible)\\n"
                                  f"            {window_id}.screen = {target_name};").replace('\\n', '\n')
                    new_screen = (f"        if ({window_id}.visible "
                                  f"&& {window_id}.screen !== {target_name})\\n"
                                  f"            {window_id}.visible = false;\\n"
                                  f"        {window_id}.screen = {target_name};").replace('\\n', '\n')
                    if text.count(old_screen) != 1:
                        raise ValueError(f"Missing Sway output handoff: {path.name}")
                    text = text.replace(old_screen, new_screen, 1)
                if path.name == "shell.qml":
                    text = text.replace("//@ pragma ShellId awtarchy", "//@ pragma ShellId awtarchy-sway")
                    text = text.replace("awtarchy-quickshell", "awtarchy-sway-quickshell")
                if path.name == "Bar.qml":
                    # Sway has a separate active workspace on every output;
                    # focused is true on only one output. Show each visible
                    # empty workspace, not just the globally focused one.
                    predicate = 'return workspace.focused || workspace.toplevels.values.length > 0;'
                    if text.count(predicate) != 1:
                        raise ValueError("Sway workspace visibility predicate changed")
                    text = text.replace(
                        predicate,
                        'return workspace.focused || workspace.active '
                        '|| workspace.toplevels.values.length > 0;', 1)
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
                    # Both horizontal and vertical workspace arrows must be
                    # translated. Reject source drift instead of keeping a
                    # runnable-looking Hyprland command in the Sway shell.
                    for arrow in ("arrowSlot", "arrowSlotVertical"):
                        matches = [
                            line.strip() for line in text.splitlines()
                            if 'onClicked: Quickshell.execDetached(["hyprctl"' in line
                            and arrow + ".modelData.dir" in line
                        ]
                        if len(matches) != 1:
                            raise ValueError(
                                "Missing or duplicated workspace arrow: " + arrow
                            )
                        text = text.replace(
                            matches[0],
                            'onClicked: SwayBridge.moveWorkspace('
                            + arrow + '.modelData.dir)'
                        )
                if path.name == "Bar.qml":
                    # Layer-shell bars cannot be moved with Sway's window
                    # floating_modifier. Capture ALT+left drag in the bar Item
                    # and forward the preview/commit through Quickshell itself.
                    props = '    property bool wsDrawerOpen: false'
                    if text.count(props) != 1:
                        raise ValueError("Bar root state changed")
                    text = text.replace(props, props + '''
    property bool swayDragActive: false
    property string swayDragCandidate: "none"

    function beginSwayDrag() {
        swayDragActive = true;
        swayDragCandidate = "none";
        console.info("SwayBarDrag: received ALT+left press", monitorName);
        SwayDragBridge.beginBarDrag(monitorName);
    }
    function previewSwayDrag(dx, dy) {
        if (!swayDragActive || Math.max(Math.abs(dx), Math.abs(dy)) < 18)
            return;
        const candidate = Math.abs(dx) * 1.2 >= Math.abs(dy)
            ? (dx > 0 ? "right" : "left")
            : (dy > 0 ? "bottom" : "top");
        if (candidate !== swayDragCandidate) {
            swayDragCandidate = candidate;
            SwayDragBridge.previewBarDrag(monitorName, candidate);
        }
    }
    function finishSwayDrag() {
        if (!swayDragActive)
            return;
        swayDragActive = false;
        console.info("SwayBarDrag: released", monitorName, swayDragCandidate);
        SwayDragBridge.finishBarDrag(monitorName, swayDragCandidate);
        swayDragCandidate = "none";
    }
''')
                    for orientation, layout in (
                        ("Horizontal", "horizontalLayout"),
                        ("Vertical", "verticalLayout"),
                    ):
                        anchor = '    Item {\n        id: ' + layout + '\n'
                        if text.count(anchor) != 1:
                            raise ValueError("Missing Sway bar layout: " + layout)
                        handler = '''
        DragHandler {
            id: swayBarDragORIENTATION
            acceptedButtons: Qt.LeftButton
            acceptedModifiers: Qt.AltModifier
            target: null
            dragThreshold: 5
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: {
                if (active)
                    bar.beginSwayDrag();
                else
                    bar.finishSwayDrag();
            }
            onActiveTranslationChanged: {
                if (active)
                    bar.previewSwayDrag(activeTranslation.x, activeTranslation.y);
            }
        }
'''.replace("ORIENTATION", orientation)
                        text = text.replace(anchor, anchor + handler, 1)
                if path.name == "shell.qml":
                    # Direct signals preserve drag event ordering and avoid
                    # subprocess races between begin/preview/finish.
                    needle = '    IpcHandler {\n        target: "control"'
                    if text.count(needle) != 1:
                        raise ValueError("Quickshell control section changed")
                    text = text.replace(needle, '''    Connections {
        target: SwayDragBridge
        function onBeginBarDrag(monitor) { root.beginBarDrag(monitor); }
        function onPreviewBarDrag(monitor, candidate) {
            root.previewBarDrag(monitor, candidate);
        }
        function onFinishBarDrag(monitor, candidate) {
            root.finishBarDrag(monitor, candidate);
        }
    }

''' + needle)
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
                if path.name == "Theme.qml":
                    old_theme = '/quickshell/awtarchy/theme.json'
                    if text.count(old_theme) != 1:
                        raise ValueError("Quickshell theme path changed; refusing port")
                    text = text.replace(old_theme, '/quickshell/awtarchy-sway/theme.json')
                if path.name == "ThemePicker.qml":
                    if '/sway/awtarchy-trial/theme-apply.sh' not in text:
                        raise ValueError("ThemePicker still uses Hyprland apply backend")
                    state_name = '/awtarchy/active-theme'
                    if text.count(state_name) != 1:
                        raise ValueError("ThemePicker active state location changed")
                    text = text.replace(state_name, '/awtarchy/active-theme-sway')
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
