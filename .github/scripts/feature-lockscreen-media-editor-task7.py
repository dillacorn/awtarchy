from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one {label} target, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


editor = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
replace_once(
    editor,
    'statusMessage = "Image spawn animation updated. Use Play Spawn to preview.";',
    'statusMessage = "Media spawn animation updated. Use Play Spawn to preview.";',
    "spawn-animation wording",
)
replace_once(
    editor,
    'statusMessage = "Image spawn timing updated. Use Play Spawn to preview.";',
    'statusMessage = "Media spawn timing updated. Use Play Spawn to preview.";',
    "spawn-timing wording",
)
replace_once(
    editor,
    'if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1);',
    'if (isCustomImage(name)) return "Media " + (customImageIndex(name) + 1);',
    "custom-media element label",
)

contract = Path("tests/test-quickshell-lockscreen-media-editor-polish.sh")
text = contract.read_text(encoding="utf-8")
anchor = '''require_text "$EDITOR" 'Esc Cancel' \\
    'editor does not advertise its cancel shortcut'\n'''
addition = anchor + '''[[ "$(grep -Fc -- 'readonly property real dragActivationThresholdPx: 5' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor drag activation threshold is declared more than once'\n[[ "$(grep -Fc -- 'sequence: \"Ctrl+S\"' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor Ctrl+S save shortcut is declared more than once'\n[[ "$(grep -Fc -- 'Ctrl+S Save  •  Esc Cancel' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor shortcut hint is rendered more than once'\nrequire_text "$EDITOR" 'return "Media " + (customImageIndex(name) + 1)' \\
    'custom media elements still use Image as their visible editor label'\nrequire_text "$EDITOR" 'Media spawn animation updated. Use Play Spawn to preview.' \\
    'custom media spawn-animation status still uses Image wording'\nrequire_text "$EDITOR" 'Media spawn timing updated. Use Play Spawn to preview.' \\
    'custom media spawn-timing status still uses Image wording'\n'''
if addition not in text:
    if text.count(anchor) != 1:
        raise SystemExit("media/editor contract shortcut anchor changed")
    text = text.replace(anchor, addition, 1)

anchor = '''require_text "$QUICK_SETTINGS" 'text: "Super + Alt + E"' \\
    'Quick Settings does not advertise the direct editor shortcut'\n'''
addition = anchor + '''[[ "$(grep -Fc -- 'function openLockscreenEditor(): void { LockscreenEditor.openFocused(); }' "$SHELL_QML")" -eq 1 ]] \\
    || fail 'desktop shell lockscreen-editor IPC action is duplicated'\n[[ "$(grep -Fc -- 'text: "Super + Alt + E"' "$QUICK_SETTINGS")" -eq 1 ]] \\
    || fail 'Quick Settings lockscreen-editor shortcut hint is duplicated'\n[[ "$(grep -Fc -- 'local lockscreen_editor = "~/.config/hypr/scripts/quickshell_lockscreen_editor.sh"' "$HYPRLAND")" -eq 1 ]] \\
    || fail 'Hyprland lockscreen-editor launcher variable is duplicated'\n[[ "$(grep -Fc -- 'hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})' "$HYPRLAND")" -eq 1 ]] \\
    || fail 'Super+Alt+E lockscreen-editor bind is duplicated'\n'''
if addition not in text:
    if text.count(anchor) != 1:
        raise SystemExit("media/editor contract shortcut-hint anchor changed")
    text = text.replace(anchor, addition, 1)
contract.write_text(text, encoding="utf-8")
