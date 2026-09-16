#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"missing/ambiguous patch target: {label}")
    path.write_text(text.replace(old, new, 1))


shell = Path("config/quickshell/awtarchy/shell.qml")
replace_once(
    shell,
    '        function hardReload(): void { Quickshell.reload(true); }\n',
    '        function hardReload(): void { Quickshell.reload(true); }\n'
    '        function openLockscreenEditor(): void { LockscreenEditor.openFocused(); }\n',
    "editor IPC action",
)

quick = Path("config/quickshell/awtarchy/QuickSettings.qml")
replace_once(
    quick,
    '''                                        SettingsButton {
                                            Layout.fillWidth: true
                                            label: "Edit Layout"
                                            active: true
                                            textSize: root.scaledText(9)
                                            onClicked: root.openLockscreenEditor()
                                        }
''',
    '''                                        SettingsButton {
                                            Layout.fillWidth: true
                                            label: "Edit Layout"
                                            active: true
                                            textSize: root.scaledText(9)
                                            onClicked: root.openLockscreenEditor()
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Super + Alt + E"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignHCenter
                                        }
''',
    "Quick Settings editor shortcut hint",
)

hypr = Path("config/hypr/hyprland.lua")
replace_once(
    hypr,
    'local hypr_quicksettings = "~/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"\n',
    'local hypr_quicksettings = "~/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"\n'
    'local lockscreen_editor = "~/.config/hypr/scripts/quickshell_lockscreen_editor.sh"\n',
    "Hyprland editor launcher variable",
)
replace_once(
    hypr,
    'hl.bind("SUPER + ALT + backspace", hl.dsp.exec_cmd(hypr_quicksettings), {})\n',
    'hl.bind("SUPER + ALT + backspace", hl.dsp.exec_cmd(hypr_quicksettings), {})\n'
    'hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})\n',
    "Hyprland editor shortcut",
)

launcher = Path("config/hypr/scripts/quickshell_lockscreen_editor.sh")
launcher.write_text('''#!/usr/bin/env bash
# Open the native Awtarchy lockscreen layout editor.

set -euo pipefail

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call control openLockscreenEditor
''')
launcher.chmod(0o755)
