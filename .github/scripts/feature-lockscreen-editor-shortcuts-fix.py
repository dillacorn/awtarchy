from pathlib import Path
import hashlib

editor = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
text = editor.read_text(encoding="utf-8")

outer = '''    Shortcut { sequence: "Ctrl+S"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.close() }

'''
if text.count(outer) != 1:
    raise SystemExit(f"expected one singleton save/cancel shortcut block, found {text.count(outer)}")
text = text.replace(outer, "", 1)

anchor = '''        Shortcut { sequence: "Ctrl+A"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; onActivated: root.selectAllElements() }
'''
insert = anchor + '''        Shortcut { id: editorSaveShortcut; sequence: "Ctrl+S"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }
        Shortcut { id: editorCancelShortcut; sequence: "Escape"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.close() }
'''
if text.count(anchor) != 1:
    raise SystemExit(f"expected one editor-window shortcut anchor, found {text.count(anchor)}")
text = text.replace(anchor, insert, 1)
editor.write_text(text, encoding="utf-8")

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
history_text = history.read_text(encoding="utf-8")
digest = hashlib.sha256(editor.read_bytes()).hexdigest()
line = f"{digest}\t.config/quickshell/awtarchy/LockscreenEditor.qml"
if line not in history_text:
    if not history_text.endswith("\n"):
        history_text += "\n"
    history_text += f"\n# 2026-09-16 lockscreen editor window-owned save/cancel shortcuts.\n{line}\n"
    history.write_text(history_text, encoding="utf-8")
